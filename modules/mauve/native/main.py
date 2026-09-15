#!/usr/bin/env python3
"""Mauve native 标准入口驱动（Mauve / progressiveMauve 2.4.0）。

Mauve 是多基因组比对与可视化系统：progressiveMauve 构建多基因组比对（识别同源区与
大尺度重排/倒位），输出 XMFA 比对 + backbone 保守区坐标；Mauve（GUI）可视化结构变异。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align genome1.fasta genome2.fasta genome3.fasta \
       --output=alignment.xmfa --backbone-output=alignment.backbone
   python main.py apply_backbone alignment.xmfa --output=rebuilt.xmfa
   python main.py gui alignment.xmfa
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令形态（参数名取自官方 progressiveMauve 手册 user-guide/progressivemauve.html）：
  progressiveMauve [--output=<file>] [--backbone-output=<file>] [--output-guide-tree=<file>]
                   [--seed-weight=<n>] [--weight=<n>] [--min-scaled-penalty=<n>]
                   [--disable-backbone] [--collinear] [--mums] [--seed-family]
                   [--scratch-path-1=<path>] <genome1> <genome2> ...
  progressiveMauve --apply-backbone=<xmfa> --output=<file> [--hmm-p-go-homologous=<p> ...]
  mauve <alignment.xmfa>            # GUI 可视化（官方 tarball 启动脚本名为 Mauve）

注意：progressiveMauve / Mauve 为 Java 工具（单线程）——--threads 仅占位接受，不注入命令行；
      JVM 堆设置经 JAVA_OPTS 环境变量透传（GUI 启动脚本 Mauve 内置 JAVA_ARGS，需更大堆时改脚本）；
      --tmpdir 映射为 progressiveMauve 的 --scratch-path-1=<tmpdir>。
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
    "align": "多基因组比对（progressiveMauve）→ --output=<alignment.xmfa> [+ --backbone-output]",
    "apply_backbone": "对已有 XMFA 重新评估 backbone（progressiveMauve --apply-backbone=<xmfa>）",
    "gui": "用 Mauve 图形界面查看比对结果（mauve <alignment.xmfa>，需图形环境）",
}

# 子命令 -> 官方可执行名（GUI 启动脚本官方名为 Mauve）
_BINARIES = {
    "align": "progressiveMauve",
    "apply_backbone": "progressiveMauve",
    "gui": "Mauve",
}


class MauveSkill(base.SkillBase):
    software = "mauve"
    binary = "progressiveMauve"

    def __init__(self, meta_path: str | Path | None = None):
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令惰性解析官方可执行文件（测试通过 monkeypatch 本方法避开安装依赖）。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 Mauve（mamba create -n mauve "
                f"-c conda-forge -c bioconda mauve=2.4.0.r4736，或解压官方预编译 tarball；"
                f"见 README「环境安装」）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        progressiveMauve/Mauve 单线程，该值仅用于上层调度语义（不注入命令行）。
        """
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 progressiveMauve / mauve 命令行（返回 argv，由 run()/main() 执行）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_sub_binary(subcommand)
        cmd: list[str] = [binary]

        if subcommand == "gui":
            alignment = kw.get("alignment")
            if not alignment:
                raise ValueError("gui 需要 alignment（输入的 XMFA 比对文件）")
            cmd.append(str(alignment))
        elif subcommand == "apply_backbone":
            alignment = kw.get("alignment")
            if not alignment:
                raise ValueError("apply_backbone 需要 alignment（输入的 XMFA 比对文件）")
            cmd.append(f"--apply-backbone={alignment}")
            self._append_common(cmd, kw, want_tmpdir=True)
            if kw.get("homology_prob") is not None:
                cmd.append(f"--hmm-p-go-homologous={kw['homology_prob']}")
            if kw.get("unrelated_prob") is not None:
                cmd.append(f"--hmm-p-go-unrelated={kw['unrelated_prob']}")
        elif subcommand == "align":
            genomes = kw.get("genomes") or []
            if isinstance(genomes, str):
                genomes = [genomes]
            if len(genomes) < 1:
                raise ValueError("align 需要 genomes（一个或多个基因组 FASTA/GenBank 文件）")
            if kw.get("output"):
                cmd.append(f"--output={kw['output']}")
            if kw.get("backbone_output"):
                cmd.append(f"--backbone-output={kw['backbone_output']}")
            if kw.get("output_guide_tree"):
                cmd.append(f"--output-guide-tree={kw['output_guide_tree']}")
            if kw.get("input_guide_tree"):
                cmd.append(f"--input-guide-tree={kw['input_guide_tree']}")
            if kw.get("seed_weight") is not None:
                cmd.append(f"--seed-weight={int(kw['seed_weight'])}")
            if kw.get("weight") is not None:
                cmd.append(f"--weight={int(kw['weight'])}")
            if kw.get("min_scaled_penalty") is not None:
                cmd.append(f"--min-scaled-penalty={int(kw['min_scaled_penalty'])}")
            if kw.get("disable_backbone"):
                cmd.append("--disable-backbone")
            if kw.get("collinear"):
                cmd.append("--collinear")
            if kw.get("mums"):
                cmd.append("--mums")
            if kw.get("seed_family"):
                cmd.append("--seed-family")
            self._append_tmpdir(cmd, kw)
            cmd += [str(g) for g in genomes]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def _append_common(self, cmd: list[str], kw: dict, *, want_tmpdir: bool) -> None:
        """输出/backbone 相关通用参数（apply_backbone 复用）。"""
        if kw.get("output"):
            cmd.append(f"--output={kw['output']}")
        if kw.get("backbone_output"):
            cmd.append(f"--backbone-output={kw['backbone_output']}")
        if want_tmpdir:
            self._append_tmpdir(cmd, kw)

    def _append_tmpdir(self, cmd: list[str], kw: dict) -> None:
        """progressiveMauve 临时目录：--scratch-path-1=<tmpdir>。"""
        tmpdir = kw.get("tmpdir") or self.tmpdir
        if tmpdir:
            cmd.append(f"--scratch-path-1={tmpdir}")

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mauve-skill",
        description="Mauve / progressiveMauve 2.4.0 native 技能驱动（多基因组比对与可视化；Java 单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("genomes", nargs="+", help="输入基因组（FASTA/GenBank，多个）")
    pa.add_argument("--output", help="输出 XMFA 比对文件（默认写 stdout）")
    pa.add_argument("--backbone-output", dest="backbone_output", help="backbone 保守区坐标输出文件")
    pa.add_argument("--output-guide-tree", dest="output_guide_tree", help="输出引导树（NEWICK）")
    pa.add_argument("--input-guide-tree", dest="input_guide_tree", help="输入引导树（NEWICK）")
    pa.add_argument("--seed-weight", dest="seed_weight", type=int, help="初始锚点种子权重")
    pa.add_argument("--weight", type=int, help="最小 LCB 权重/断点罚分")
    pa.add_argument("--min-scaled-penalty", dest="min_scaled_penalty", type=int,
                    help="缩放后最小断点罚分")
    pa.add_argument("--disable-backbone", dest="disable_backbone", action="store_true",
                    help="关闭 backbone 检测")
    pa.add_argument("--collinear", action="store_true", help="假定输入序列共线（无重排）")
    pa.add_argument("--mums", action="store_true", help="仅求 MUM（不做 LCB 判断）")
    pa.add_argument("--seed-family", dest="seed_family", action="store_true",
                    help="使用 spaced seed family 提升灵敏度")
    pa.add_argument("--extra-args", help="透传给 progressiveMauve 的额外参数")
    _add_runtime_opts(pa)

    # apply_backbone
    pb = sub.add_parser("apply_backbone", help=SUBCOMMANDS["apply_backbone"])
    pb.add_argument("alignment", help="输入的 XMFA 比对文件")
    pb.add_argument("--output", help="输出 XMFA 文件（默认写 stdout）")
    pb.add_argument("--backbone-output", dest="backbone_output", help="backbone 输出文件")
    pb.add_argument("--hmm-p-go-homologous", dest="homology_prob", type=float,
                    help="同源 HMM 转移概率（默认 0.0001）")
    pb.add_argument("--hmm-p-go-unrelated", dest="unrelated_prob", type=float,
                    help="非同源 HMM 转移概率（默认 0.000001）")
    pb.add_argument("--extra-args", help="透传给 progressiveMauve 的额外参数")
    _add_runtime_opts(pb)

    # gui
    pg = sub.add_parser("gui", help=SUBCOMMANDS["gui"])
    pg.add_argument("alignment", help="输入的 XMFA 比对文件")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=str, default="auto",
                   help="占位（Mauve 单线程，不注入命令行；auto 或正整数均接受）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（align/apply_backbone 映射为 --scratch-path-1）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = MauveSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MauveSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = None if ns.threads in (None, "auto") else ns.threads
    kw["tmpdir"] = getattr(ns, "tmpdir", None) or skill.tmpdir

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
