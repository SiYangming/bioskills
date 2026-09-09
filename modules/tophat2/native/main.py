#!/usr/bin/env python3
"""tophat2 native 标准入口驱动（TopHat2 2.1.1；说明型）。

⚠️ DEPRECATED：本模块登记的是 TopHat2（CCB，Tuxedo 家族；Kim D et al. Genome Biol
2013）。官方 CCB 页面明示 TopHat 进入低维护阶段、"largely superseded by HISAT2"
（更准更快）——新项目请用 HISAT2 / STAR。

本驱动为「说明型 + 命令构造」：不实际运行 tophat（软件 deprecated、无新用场景），
按官方 manual 构造命令行，供历史复现 / 文档化调用 / Agent 展示：
  tophat [-o <out_dir>] [-p <threads>] [-G <gtf>] [--transcriptome-index <idx>]
         [-N <mismatches>] [--read-edit-dist <n>] [--max-multihits <n>]
         [-r <inner_dist>] <genome_index_base> <reads...>
  主产物：<out_dir>/accepted_hits.bam（默认过滤多比对）、junctions.bed、
         align_summary.txt、insertions.bed / deletions.bed

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py tophat genome_index reads_1.fq reads_2.fq \
       -o tophat_out -p 8 -G genes.gtf
   python main.py tophat genome_index --transcriptome-index tx_idx \
       reads_1.fq reads_2.fq -p 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 TopHat2（tophat 在 PATH；bioconda tophat=2.1.2 或 CCB 官方 2.1.1，
见 README「环境安装」），且目标基因组已有 Bowtie2 索引（<base>.1.bt2）。
本驱动不执行真实比对（仅命令构造）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "tophat": "TopHat2 RNA-seq 剪接比对命令构造（-o/-p/-G/--transcriptome-index；已废弃，仅供历史参考）",
}

_BINARIES = {"tophat": "tophat"}

DEPRECATED_NOTE = (
    "⚠️ TopHat2 已淘汰（官方 CCB 明示 largely superseded by HISAT2：更准更快；"
    "最终发布 2.1.1，2016-02-23）：本模块仅作历史参考登记，以下命令构造仅供复现"
    "历史分析，新项目请用 HISAT2 / STAR。"
)


class Tophat2Skill(base.SkillBase):
    software = "tophat2"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（tophat），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 TopHat2（mamba create -n "
                f"tophat2-native -c conda-forge -c bioconda tophat=2.1.2 bowtie2，"
                f"或 CCB 官方 2.1.1；见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """tophat：构造（不执行）历史 TopHat2 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "tophat":
            return self._build_tophat(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _build_tophat(self, bin_path: str, **kw) -> list[str]:
        genome_index_base = kw.get("genome_index_base")
        reads = kw.get("reads") or []
        read_list = [reads] if isinstance(reads, str) else [r for r in reads if r]
        if not genome_index_base:
            raise RuntimeError("tophat 需要 <genome_index_base>（Bowtie2 索引 basename）")
        if not read_list:
            raise RuntimeError("tophat 需要至少一个 reads 文件（位置参数）")

        cmd = [bin_path]
        cmd += ["-o", self._abspath(str(kw.get("out_dir") or "tophat_out"))]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-p", str(int(threads))]
        else:
            cmd += ["-p", "4"]   # TopHat2 默认单线程，驱动按 optimization.default 给 4
        if kw.get("gtf"):
            cmd += ["-G", self._abspath(kw["gtf"])]
        if kw.get("transcriptome_index"):
            cmd += ["--transcriptome-index", str(kw["transcriptome_index"])]
        if kw.get("read_mismatches") is not None:
            cmd += ["-N", str(int(kw["read_mismatches"]))]
        if kw.get("read_edit_dist") is not None:
            cmd += ["--read-edit-dist", str(int(kw["read_edit_dist"]))]
        if kw.get("max_multihits") is not None:
            cmd += ["--max-multihits", str(int(kw["max_multihits"]))]
        if kw.get("inner_dist") is not None:
            cmd += ["-r", str(int(kw["inner_dist"]))]
        cmd.append(str(genome_index_base))
        for r in read_list:
            cmd.append(str(r))   # reads 可为逗号列表，保持原样透传
        return cmd
        # 产物 <out_dir>/accepted_hits.bam 等（CLI 层给 hint）


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="tophat2-skill",
        description="TopHat2 native 技能驱动（说明型：构造历史 tophat 命令，已废弃，"
                    "仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pt = sub.add_parser("tophat", help=SUBCOMMANDS["tophat"])
    pt.add_argument("genome_index_base", help="Bowtie/Bowtie2 基因组索引 basename")
    pt.add_argument("reads", nargs="+", help="reads 文件（FASTQ/FASTA；SE 1 个，PE 2 个）")
    pt.add_argument("-o", "--output-dir", dest="out_dir", default="tophat_out",
                    help="输出目录（默认 tophat_out）")
    pt.add_argument("-G", "--GTF", dest="gtf", help="注释 GTF/GFF（自动建 transcriptome index）")
    pt.add_argument("--transcriptome-index", dest="transcriptome_index",
                    help="预建 transcriptome 索引 basename")
    pt.add_argument("-N", "--read-mismatches", dest="read_mismatches", type=int,
                    help="每条 read 允许错配数（默认 2）")
    pt.add_argument("--read-edit-dist", dest="read_edit_dist", type=int,
                    help="最终比对 edit distance（默认 2）")
    pt.add_argument("--max-multihits", dest="max_multihits", type=int,
                    help="多比对 read 最大报告数（默认 20）")
    pt.add_argument("-r", "--inner-dist", dest="inner_dist", type=int,
                    help="双端 inner distance 期望均值（PE）")
    _add_runtime_opts(pt)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，tophat -p）或 auto（默认 4）。"""
    v = str(value).strip().lower()
    if v == "auto":
        return "auto"
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=_threads_arg, default=None,
                   help="线程数：auto（默认，-p 4）或正整数（tophat -p N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Tophat2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Tophat2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir",
                       "genome_index_base", "reads") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "tophat":
        kw["genome_index_base"] = ns.genome_index_base
        kw["reads"] = ns.reads

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    out_dir = getattr(ns, "out_dir", "tophat_out")
    print(f"[hint] 主产物 <{out_dir}>/accepted_hits.bam、junctions.bed、"
          f"align_summary.txt（需 Bowtie2 索引 <genome_index_base>.1.bt2 已建）",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
