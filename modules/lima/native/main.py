#!/usr/bin/env python3
"""lima native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py lima reads.bam primers.fasta out/demux.bam -j 8 --isoseq
   python main.py lima --reads reads.bam --primers primers.fasta --outdir out --prefix demux --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/lima_analysis.py
与 workflow/modules/lima/snakemake/local/lima.smk：lima <reads> <primers> <out> [-j N] [extra]。
输出扩展名根据输入格式自动推断（bam/fasta.gz/fastq.gz/...）。
"""

from __future__ import annotations

import argparse
import json
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
    "lima": "PacBio 条形码拆分与引物去除（Iso-Seq 第二步）",
}


class LimaSkill(base.SkillBase):
    software = "lima"
    binary = "lima"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    @staticmethod
    def _infer_out_ext(reads_path: str) -> str:
        name = Path(reads_path).name
        for suf in (".fasta.gz", ".fastq.gz", ".bam", ".fasta", ".fastq"):
            if name.endswith(suf):
                return suf.lstrip(".")
        return "bam"

    @staticmethod
    def _derive_prefix(reads_path: str) -> str:
        name = Path(reads_path).name
        for suf in (".bam", ".fasta.gz", ".fastq.gz", ".fasta", ".fastq"):
            if name.endswith(suf):
                return name[: -len(suf)]
        return Path(reads_path).stem

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 lima 命令行。"""
        if subcommand != "lima":
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        reads = kw.get("reads") or kw.get("input")
        primers = kw.get("primers")
        if not reads:
            raise ValueError("缺少必填参数 reads（输入 reads 文件）")
        if not primers:
            raise ValueError("缺少必填参数 primers（引物 FASTA）")

        # 输出路径：显式 output > outdir/prefix.<ext>
        out_path = kw.get("output")
        if not out_path:
            ext = self._infer_out_ext(reads)
            prefix = kw.get("prefix") or self._derive_prefix(reads)
            outdir = kw.get("outdir")
            if outdir:
                outdir_path = Path(outdir)
            else:
                outdir_path = Path(reads).parent
            out_path = str(outdir_path / f"{prefix}.{ext}")

        cmd += [str(reads), str(primers), out_path]

        # 常用开关
        if kw.get("isoseq"):
            cmd.append("--isoseq")
        if kw.get("peek_guess"):
            cmd.append("--peek-guess")
        if kw.get("min_score") is not None:
            cmd += ["--min-score", str(kw["min_score"])]

        # 线程注入
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-j", str(threads)]

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
        prog="lima-skill",
        description="lima native 技能驱动（自动线程/内存优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pl = sub.add_parser("lima", help=SUBCOMMANDS["lima"])
    pl.add_argument("--reads", help="输入 reads 文件（bam/fasta/fasta.gz/fastq/fastq.gz）")
    pl.add_argument("--input", help="输入 reads 文件的别名")
    pl.add_argument("--primers", help="引物 FASTA 文件")
    pl.add_argument("-o", "--output", help="输出文件路径（缺省自动生成）")
    pl.add_argument("-d", "--outdir", help="输出目录")
    pl.add_argument("--prefix", help="输出前缀（默认从 reads 文件名推断）")
    pl.add_argument("--isoseq", action="store_true", help="Iso-Seq 模式（末端识别优化）")
    pl.add_argument("--peek-guess", action="store_true", help="peek 模式猜测引物对")
    pl.add_argument("--min-score", type=float, help="最小比对得分阈值")
    pl.add_argument("--extra-args", help="透传给 lima 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pl)

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
        skill = LimaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LimaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    # lima 无 stdout 输出；stderr 直接透传
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
