#!/usr/bin/env python3
"""blasr native 标准入口驱动（BLASR 5.3.5；说明型）。

⚠️ DEPRECATED：本模块登记的是 BLASR（PacBio 首个长读比对器，Chaisson & Tesler,
BMC Bioinformatics 2012）。官方仓库 PacificBiosciences/blasr 2026-09 已不可达
（404），官方继任者 pbmm2（README 明示 "official replacement for BLASR"）/
minimap2——新项目请用 minimap2 / pbmm2。

本驱动为「说明型 + 命令构造」：不实际运行 blasr（软件 deprecated、官方仓库 404），
按官方用法构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. sawriter：参考 FASTA → .sa 后缀数组索引
   sawriter <reference.fasta> <out.sa>
2. blasr：reads + 参考 + .sa → 比对输出
   blasr <reads> <reference.fasta> <reference.sa>
         [--out out.bam --bam | --out out.sam --sam] [--nproc N]
         [--bestn 10] [--minPctIdentity 70]

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py sawriter ref.fa ref.sa
   python main.py blasr subreads.fasta ref.fa ref.sa --out aln.bam --bam \
       --nproc 8 --bestn 10
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 BLASR（blasr / sawriter 在 PATH，bioconda blasr=5.3.5 等，见 README
「环境安装」）。本驱动不执行真实比对（仅命令构造）。
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
    "sawriter": "参考 FASTA → .sa 后缀数组索引（命令构造；仅历史复现）",
    "blasr": "PacBio 长读比对命令构造（reads+参考+.sa → SAM/BAM；已废弃，仅供历史参考）",
}

# 子命令 → 真实可执行名（blasr 5.3.5 下即此名）
_BINARIES = {"sawriter": "sawriter", "blasr": "blasr"}

DEPRECATED_NOTE = (
    "⚠️ BLASR 已淘汰（PacBio 官方仓库 404；官方继任者 pbmm2 / minimap2）：本模块仅作"
    "历史参考登记，以下命令构造仅供复现历史分析，新项目请用 minimap2 / pbmm2。"
)


class BlasrSkill(base.SkillBase):
    software = "blasr"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（sawriter / blasr），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 BLASR（mamba create -n "
                f"blasr-native -c conda-forge -c bioconda blasr=5.3.5，或源码走 fork "
                f"mchaisso/blasr；见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """sawriter / blasr：构造（不执行）历史 BLASR 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "sawriter":
            return self._build_sawriter(bin_path, **kw)
        if subcommand == "blasr":
            return self._build_blasr(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- sawriter ---------------------------------------------------------- #
    def _build_sawriter(self, bin_path: str, **kw) -> list[str]:
        reference = kw.get("reference")
        out_sa = kw.get("out_sa")
        if not reference:
            raise RuntimeError("sawriter 需要 --reference（参考 FASTA）")
        if not out_sa:
            raise RuntimeError("sawriter 需要 --out-sa（输出 .sa 索引路径）")
        return [bin_path, self._abspath(reference), self._abspath(out_sa)]

    # -- blasr ------------------------------------------------------------- #
    def _build_blasr(self, bin_path: str, **kw) -> list[str]:
        reads = kw.get("reads")
        reference = kw.get("reference")
        sa_file = kw.get("sa_file")
        if not reads:
            raise RuntimeError("blasr 需要 --reads（输入 PacBio reads）")
        if not reference:
            raise RuntimeError("blasr 需要 --reference（参考 FASTA）")
        if not sa_file:
            raise RuntimeError("blasr 需要 --sa-file（sawriter 产出的 .sa 索引）")

        sam = bool(kw.get("sam"))
        bam = bool(kw.get("bam"))
        if sam and bam:
            raise RuntimeError("--sam 与 --bam 只能二选一")

        cmd = [bin_path,
               self._abspath(reads),
               self._abspath(reference),
               self._abspath(sa_file)]
        if kw.get("out"):
            cmd += ["--out", self._abspath(kw["out"])]
        if kw.get("bestn") is not None:
            cmd += ["--bestn", str(int(kw["bestn"]))]
        if kw.get("min_pct_identity") is not None:
            cmd += ["--minPctIdentity", str(float(kw["min_pct_identity"]))]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["--nproc", str(int(threads))]
        else:
            cmd += ["--nproc", "4"]   # 驱动默认（optimization.default_cpus）
        if sam:
            cmd.append("--sam")
        if bam:
            cmd.append("--bam")
        return cmd  # 输出 SAM/BAM（未给 --sam/--bam 时为 blasr 原生格式）


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="blasr-skill",
        description="BLASR native 技能驱动（说明型：构造历史 sawriter/blasr 命令，"
                    "已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    ps = sub.add_parser("sawriter", help=SUBCOMMANDS["sawriter"])
    ps.add_argument("reference", help="参考基因组 FASTA")
    ps.add_argument("out_sa", help="输出 .sa 索引文件路径")
    _add_runtime_opts(ps)

    pb = sub.add_parser("blasr", help=SUBCOMMANDS["blasr"])
    pb.add_argument("reads", help="输入 PacBio reads（FASTA/FASTQ）")
    pb.add_argument("reference", help="参考基因组 FASTA")
    pb.add_argument("sa_file", help="sawriter 产出的 .sa 索引文件")
    pb.add_argument("--out", help="输出文件（--bam 需 .bam；--sam 需 .sam）")
    fmt = pb.add_mutually_exclusive_group()
    fmt.add_argument("--sam", action="store_true", help="输出 SAM（默认 blasr 原生格式）")
    fmt.add_argument("--bam", action="store_true", help="输出 BAM（PacBio 推荐）")
    pb.add_argument("--bestn", type=int, help="每 read 最多报告 hits（--bestn，默认 10）")
    pb.add_argument("--min-pct-identity", dest="min_pct_identity", type=float,
                    help="最低比对一致率阈值（--minPctIdentity，如 70）")
    _add_runtime_opts(pb)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，blasr --nproc）或 auto（默认 --nproc 4）。"""
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
                   help="线程数：auto（默认，--nproc 4）或正整数（blasr --nproc N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = BlasrSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BlasrSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir",
                       "reads", "reference", "sa_file") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "sawriter":
        kw["reference"] = ns.reference
        kw["out_sa"] = ns.out_sa
    else:
        kw["reads"] = ns.reads
        kw["reference"] = ns.reference
        kw["sa_file"] = ns.sa_file

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "sawriter":
        print(f"[hint] 产物为 .sa 后缀数组索引，供 blasr 第三位置参数使用",
              file=sys.stderr)
    else:
        print(f"[hint] --bam 输出可用于下游（历史流程常接 pbalign/GenomicConsensus "
              f"抛光）；新项目请用 minimap2/pbmm2", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
