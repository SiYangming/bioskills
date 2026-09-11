#!/usr/bin/env python3
"""barrnap native 标准入口驱动（rRNA 基因预测）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py scan genome.fa --kingdom bac --threads 8            # GFF3 走 stdout
   python main.py scan genome.fa --kingdom bac --threads 8 -o rrna.gff3
   python main.py scan genome.fa --kingdom fun --outseq rrna.fa -o rrna.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（--threads）与临时目录（--tmpdir，同时设 TMPDIR）。

版本兼容说明（barrnap 0.9 → 1.10.x 的重大 CLI 变化，见 meta.yaml software_versions）：
- 登记版本为 bioconda 现行 barrnap=1.10.6（2026-04 起，官方镜像 quay.io/biocontainers）：
  --kingdom 取值 bac/arc/fun（默认 bac），--evalue 默认 0.001；
  0.9 时代的 --lencutoff/--reject 已移除，'euk' 域由 'fun' 覆盖，'mito' 模型移除。
- nf-core / brew 仍 pin barrnap=0.9（经典 CLI：kingdom euk/bac/arc/mito，--lencutoff 0.8）。
- 本驱动运行时探测实际安装版本：0.9 环境原样支持 euk/mito/lencutoff；
  >=1.10 环境把 euk 警告后映射为 fun，mito 报错提示，lencutoff 忽略并警告。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "scan": "barrnap：基因组 FASTA → GFF3 rRNA（默认）/RNA 注释（5S/5.8S/16S/18S/23S/28S），缺省输出到 stdout",
}


class BarrnapSkill(base.SkillBase):
    software = "barrnap"
    binary = "barrnap"

    # barrnap 0.9（nf-core / brew pin）与 >=1.10（bioconda 现行 1.10.6）的 --kingdom 取值不同
    LEGACY_KINGDOMS = ("euk", "bac", "arc", "mito")   # barrnap 0.9
    MODERN_KINGDOMS = ("bac", "arc", "fun")           # barrnap >= 1.10

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/barrnap/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)
        self._version_cache: tuple[int, ...] | None = None
        self._version_tried = False

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _version(self) -> tuple[int, ...] | None:
        """探测安装的 barrnap 主版本（'barrnap --version'），失败返回 None（按 >=1.10 现代版处理）。"""
        if not self._version_tried:
            self._version_tried = True
            path = shutil.which(self.binary)
            if path:
                try:
                    proc = subprocess.run(
                        [path, "--version"], capture_output=True, text=True,
                        check=False, timeout=30,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    proc = None
                if proc is not None and proc.returncode == 0:
                    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?",
                                  (proc.stdout or "") + " " + (proc.stderr or ""))
                    if m:
                        self._version_cache = tuple(int(x) for x in m.groups() if x is not None)
        return self._version_cache

    def _is_legacy(self) -> bool:
        """barrnap < 1.0（0.9 经典 CLI，nf-core/brew pin）；探测失败按现代版处理。"""
        ver = self._version()
        return bool(ver and ver[0] == 0)

    def _normalize_kingdom(self, kingdom: str, legacy: bool) -> str:
        """把 0.9/1.10 两代 --kingdom 取值统一到当前安装版本的真实 CLI。"""
        if legacy:
            if kingdom == "fun":
                raise RuntimeError(
                    "当前 barrnap 为 0.9（经典版）：--kingdom 无 'fun' 域，真核（真菌）序列请用 "
                    "--kingdom euk（0.9 取值 euk/bac/arc/mito）"
                )
            if kingdom not in self.LEGACY_KINGDOMS:
                raise RuntimeError(
                    f"未知 --kingdom '{kingdom}'（barrnap 0.9 取值 euk/bac/arc/mito）"
                )
            return kingdom
        # barrnap >= 1.10（登记的现行版本 1.10.6）
        if kingdom in self.MODERN_KINGDOMS:
            return kingdom
        if kingdom == "euk":
            print(
                "[barrnap] WARNING: barrnap>=1.10 已无 'euk' 域（0.9 时代取值），"
                "真菌/真核由 'fun' 域覆盖，已把 --kingdom euk 映射为 fun",
                file=sys.stderr,
            )
            return "fun"
        if kingdom == "mito":
            raise RuntimeError(
                "当前 barrnap 为 1.10.x：'mito' 域模型已移除（0.9 时代取值）；如确需线粒体 rRNA "
                "预测请使用 barrnap=0.9（nf-core / brew pin，见 README「版本差异声明」）"
            )
        raise RuntimeError(f"未知 --kingdom '{kingdom}'（barrnap>=1.10 取值 bac/arc/fun）")

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 barrnap 命令行。"""
        threads = self._effective_threads(subcommand, kw.get("threads"))
        legacy = self._is_legacy()

        if subcommand == "scan":
            genome = kw.get("genome_fasta")
            if not genome:
                raise RuntimeError("scan 需要 genome_fasta（基因组 FASTA，位置参数）")
            kingdom = self._normalize_kingdom(str(kw.get("kingdom") or "bac"), legacy)

            cmd: list[str] = [self._resolve_binary()]
            cmd += ["--kingdom", kingdom, "--threads", str(threads)]

            outseq = kw.get("outseq")
            if outseq:
                cmd += ["--outseq", str(outseq)]
            evalue = kw.get("evalue")
            if evalue is not None:
                cmd += ["--evalue", str(evalue)]
            lencutoff = kw.get("lencutoff")
            if lencutoff is not None:
                if legacy:
                    # 0.9：按比例长度阈值把短命中标记为 partial（默认 0.8）
                    cmd += ["--lencutoff", str(lencutoff)]
                else:
                    print(
                        "[barrnap] WARNING: barrnap>=1.10 已移除 --lencutoff（CM 全局搜索不再按比例"
                        "长度过滤），已忽略该参数；0.9 环境（nf-core/brew）才会注入",
                        file=sys.stderr,
                    )

            cmd.append(str(genome))
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="barrnap-skill",
        description="barrnap native 技能驱动（自动线程/内存/IO 优化；rRNA 基因预测 → GFF3）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # scan: barrnap [--kingdom K] [--threads N] [--outseq FILE] genome.fasta > rRNA.gff3
    ps = sub.add_parser("scan", help=SUBCOMMANDS["scan"])
    ps.add_argument("genome_fasta", help="输入基因组 FASTA（可 .gz；barrnap 亦接受 GBK/EMBL/FASTQ）")
    ps.add_argument(
        "--kingdom", choices=sorted(set(("euk", "bac", "arc", "mito", "fun"))),
        default="bac",
        help="域模型：barrnap>=1.10 取 bac/arc/fun（默认 bac；euk 自动映射 fun）；barrnap 0.9 取 "
             "euk/bac/arc/mito。按安装版本自动兼容（见文件头注）",
    )
    ps.add_argument("--outseq", help="把预测 RNA（rRNA hit）序列输出到该 FASTA 文件（GFF3 仍走 stdout/-o）")
    ps.add_argument("--evalue", type=float, help="相似性 e-value 阈值（>=1.10 默认 0.001；0.9 默认 1e-6）")
    ps.add_argument(
        "--lencutoff", type=float,
        help="0.9 时代按比例长度阈值标记 partial（默认 0.8）；barrnap>=1.10 已移除，传入时自动忽略并警告",
    )
    ps.add_argument("-o", "--output", help="GFF3 输出文件（默认 stdout；由驱动写盘）")
    ps.add_argument("--extra-args", dest="extra_args", help="透传给 barrnap 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = BarrnapSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BarrnapSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # GFF3 默认写 stdout；-o/--output 由驱动落盘（避免依赖 shell 重定向）
    output_file = getattr(ns, "output", None)
    if ns.subcommand == "scan" and output_file:
        Path(output_file).write_text(result.stdout)
    else:
        if result.stdout:
            sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
