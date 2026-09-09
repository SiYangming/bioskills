#!/usr/bin/env python3
"""bedtools native 标准入口驱动。

bedtools 是 C 程序，CLI 形如：
    bedtools intersect -a a.bed -b b.bed [-v|-wa|-wb|-loj] [-f 0.1]
    bedtools merge -i in.bed [-d 100] [-s]
    bedtools sort -i in.bed
    bedtools coverage -a t.bed -b s.bam [-counts]
    bedtools genomecov -i in.bam -g genome.txt [-bg]
    bedtools bamtobed -i in.bam [-cigar]
    bedtools getfasta -fi ref.fa -bed x.bed [-name] [-s]
    bedtools subtract -a a.bed -b b.bed [-A]
conda / brew / biocontainer 提供同一 `bedtools` 可执行名；各子命令输出默认走 stdout。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py intersect -a peaks.bed -b genes.bed -wa -wb
   python main.py genomecov -i sample.bam -g hg38.genome -bg
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位 bedtools：PATH 上 `bedtools`（bioconda / brew / 官方 make 产物均可）。
- TMPDIR 经 env 注入；sort 中间量大时可结合系统 TMPDIR。
- 输出默认 stdout（bedtools 原生行为），shell 重定向/管道即可落盘。
- --dry-run 仅构造并打印 argv（不执行），供降级 argv 构造回归。
"""

from __future__ import annotations

import argparse
import json
import shlex
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "intersect": "区间求交/反选/报告原区间（-a -b；-v/-wa/-wb/-loj/-f）",
    "merge": "合并重叠/相邻区间（-i；-d 最大间隔 / -s 按链）",
    "sort": "按染色体坐标排序（-i，缺省 stdin）",
    "coverage": "区间覆盖度（-a -b；-counts 输出每区间计数）",
    "genomecov": "全基因组深度直方图 / bedGraph（-i -g [-bg]）",
    "bamtobed": "BAM → BED（-i [-cigar]）",
    "getfasta": "按 BED 区间取参考序列（-fi -bed [-name] [-s]）",
    "subtract": "区间差集（-a -b；-A 整条移除）",
}


class BedtoolsSkill(base.SkillBase):
    software = "bedtools"
    binary = "bedtools"

    def _resolve_bin(self, dry_run: bool = False) -> str:
        if dry_run:
            return self.binary
        path = base.which(self.binary)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'bedtools'，请先安装：conda/mamba（bioconda::bedtools=2.31.1）、"
                "brew（homebrew-core bedtools）、官方源码 make 或 "
                "quay.io/biocontainers/bedtools 镜像"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_bin(bool(kw.get("dry_run")))
        cmd: list[str] = [bin_path, subcommand]
        extra_tokens = str(kw.get("extra_args") or "").split()

        if subcommand in ("intersect", "coverage", "subtract"):
            a = kw.get("a")
            b = kw.get("b")
            if not a or not b:
                raise ValueError(f"{subcommand} 缺少必填参数 a / b（-a 主文件、-b 对照文件）")
            cmd += ["-a", str(a), "-b", str(b)]
            if subcommand == "intersect":
                if kw.get("min_overlap") is not None:
                    cmd += ["-f", str(kw["min_overlap"])]
                for flag in ("v", "wa", "wb", "loj", "u"):
                    if kw.get(flag):
                        cmd.append(f"-{flag}")
            elif subcommand == "coverage":
                if kw.get("counts"):
                    cmd.append("-counts")
            else:  # subtract
                if kw.get("remove_all"):
                    cmd.append("-A")
            cmd += extra_tokens
            return cmd

        if subcommand == "merge":
            inp = kw.get("input")
            if not inp:
                raise ValueError("merge 缺少必填参数 input（-i，缺省读 stdin）")
            cmd += ["-i", str(inp)]
            if kw.get("distance") is not None:
                cmd += ["-d", str(kw["distance"])]
            if kw.get("stranded"):
                cmd.append("-s")
            cmd += extra_tokens
            return cmd

        if subcommand == "sort":
            inp = kw.get("input")
            if inp:
                cmd += ["-i", str(inp)]
            if kw.get("genome"):
                cmd += ["-g", str(kw["genome"])]
            cmd += extra_tokens
            return cmd

        if subcommand == "genomecov":
            inp = kw.get("input")
            genome = kw.get("genome")
            if not inp or not genome:
                raise ValueError("genomecov 缺少必填参数 input（-i/-ibam）与 genome（-g）")
            # BAM/CRAM 输入走 -ibam；其余（BED/GFF/VCF）走 -i（bedtools 原生区隔）
            if str(inp).lower().endswith((".bam", ".cram")):
                cmd += ["-ibam", str(inp)]
            else:
                cmd += ["-i", str(inp)]
            cmd += ["-g", str(genome)]
            if kw.get("bedgraph"):
                cmd.append("-bg")
            cmd += extra_tokens
            return cmd

        if subcommand == "bamtobed":
            inp = kw.get("input")
            if not inp:
                raise ValueError("bamtobed 缺少必填参数 input（-i BAM）")
            cmd += ["-i", str(inp)]
            if kw.get("cigar"):
                cmd.append("-cigar")
            cmd += extra_tokens
            return cmd

        # getfasta
        fasta = kw.get("fasta")
        bed = kw.get("bed")
        if not fasta or not bed:
            raise ValueError("getfasta 缺少必填参数 fasta（-fi）与 bed（-bed）")
        cmd += ["-fi", str(fasta), "-bed", str(bed)]
        if kw.get("name"):
            cmd.append("-name")
        if kw.get("stranded"):
            cmd.append("-s")
        cmd += extra_tokens
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="CPU 提示（bedtools 多线程支持有限）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")
    p.add_argument("--extra-args", dest="extra_args", help="透传额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bedtools-skill",
        description="bedtools native 技能驱动（基因组区间算术；输出默认 stdout）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # -a/-b 三件套
    for name in ("intersect", "coverage", "subtract"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("-a", "--a", required=True, help="主文件 A（BED/BAM/VCF/GFF）")
        ps.add_argument("-b", "--b", required=True, help="对照文件 B")
        if name == "intersect":
            ps.add_argument("-v", action="store_true", help="反选（A 中不与 B 重叠者）")
            ps.add_argument("-wa", action="store_true", help="输出原 A 区间")
            ps.add_argument("-wb", action="store_true", help="同时输出重叠 B 区间")
            ps.add_argument("-loj", action="store_true", help="左外连接")
            ps.add_argument("-f", "--min-overlap", dest="min_overlap", type=float,
                            help="最小重叠比例（默认 1E-9）")
        elif name == "coverage":
            ps.add_argument("-counts", action="store_true", help="输出每区间重叠计数")
        else:
            ps.add_argument("-A", "--remove-all", action="store_true",
                            help="移除 A 中与 B 有任何重叠的整条区间")
        _add_runtime_opts(ps)

    pmerge = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pmerge.add_argument("-i", "--input", required=True, help="输入区间文件")
    pmerge.add_argument("-d", "--distance", type=int, help="最大合并间隔")
    pmerge.add_argument("-s", "--stranded", action="store_true", help="按链合并")
    _add_runtime_opts(pmerge)

    psort = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    psort.add_argument("-i", "--input", help="输入文件（缺省 stdin）")
    psort.add_argument("-g", "--genome", help="基因组文件（可选）")
    _add_runtime_opts(psort)

    pgc = sub.add_parser("genomecov", help=SUBCOMMANDS["genomecov"])
    pgc.add_argument("-i", "--input", required=True, help="输入 BAM/BED（-ibam 直读 BAM）")
    pgc.add_argument("-g", "--genome", required=True, help="基因组大小文件")
    pgc.add_argument("-bg", "--bedgraph", action="store_true", help="输出 bedGraph")
    _add_runtime_opts(pgc)

    pbt = sub.add_parser("bamtobed", help=SUBCOMMANDS["bamtobed"])
    pbt.add_argument("-i", "--input", required=True, help="输入 BAM")
    pbt.add_argument("-cigar", action="store_true", help="保留 CIGAR 列")
    _add_runtime_opts(pbt)

    pgf = sub.add_parser("getfasta", help=SUBCOMMANDS["getfasta"])
    pgf.add_argument("-fi", "--fasta", required=True, help="参考 FASTA（需 .fai）")
    pgf.add_argument("-bed", "--bed", required=True, help="区间 BED")
    pgf.add_argument("-name", action="store_true", help="用区间名作 FASTA 头")
    pgf.add_argument("-s", "--stranded", action="store_true", help="按链取反互补")
    _add_runtime_opts(pgf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s}  {v}")
        return 0
    if "--schema" in args:
        skill = BedtoolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BedtoolsSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "dry_run") and v is not None}
    kw["threads"] = ns.threads

    if ns.dry_run:
        try:
            cmd = skill.build_command(ns.subcommand, dry_run=True, **kw)
        except (RuntimeError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        print(shlex.join(cmd))
        return 0

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
