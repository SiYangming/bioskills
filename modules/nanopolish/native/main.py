#!/usr/bin/env python3
"""nanopolish native 标准入口驱动（继承 base.SkillBase）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py index -d fast5/ nanopore_reads.fastq
   python main.py variants --consensus -o variants.vcf -w "tig00000001:1-100000" \
       -r nanopore_reads.fastq -b reads.sorted.bam -g draft.fasta --threads 8
   python main.py vcf2fasta -g draft.fasta variants.vcf > nanopolish.fasta
   python main.py methylation -r reads.fastq -b reads.sorted.bam -g draft.fasta --threads 8
   python main.py eventalign -r reads.fastq -b reads.sorted.bam -g draft.fasta --scale-events
   python main.py phase-reads reads.sorted.bam variants.vcf --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema | --list-commands

命令逻辑（对齐教学文档 doc 04 §22 与 nanopolish 官方 CLI）：
  index       nanopolish index [-d <fast5dir>...] [-f <fast5>] [-m <moves>] [-s <summary>] <reads...>
  variants    nanopolish variants [--consensus] [-o <vcf>] [-w <region>] -r <reads> -b <bam> -g <fa> -t N
              [--methylation-aware=<dcm,dam>]
  vcf2fasta   nanopolish vcf2fasta [-g <fa>] [-f <fai>] [--methylation] <vcf>（结果写 stdout）
  methylation nanopolish methylation -r <reads> -b <bam> -g <fa> [-w <region>] -t N
  eventalign  nanopolish eventalign -r <reads> -b <bam> -g <fa> [--scale-events] -t N
  phase-reads nanopolish phase-reads <bam> <vcf> -t N
线程优先级：用户显式 --threads > optimization.per_subcommand_threads > default_cpus（-t 注入）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "index": "建立 fast5 与 reads 的索引（nanopolish index -d <fast5dir> <reads...>）",
    "variants": "信号级变异调用 / 一致性序列（nanopolish variants [--consensus] -r -b -g -t）",
    "vcf2fasta": "VCF -> 修正后 FASTA（nanopolish vcf2fasta -g <fa> <vcf>，结果写 stdout）",
    "methylation": "甲基化修饰检测（nanopolish methylation -r -b -g -t）",
    "eventalign": "将 reads 事件序列比对到参考（nanopolish eventalign -r -b -g -t）",
    "phase-reads": "reads 单倍型分型（nanopolish phase-reads <bam> <vcf> -t）",
}


def _as_list(val) -> list[str]:
    """把 argv 参数（字符串 / 列表）统一成非空字符串列表。"""
    if val is None:
        return []
    if isinstance(val, str):
        return [val] if val else []
    return [str(v) for v in val if str(v)]


class NanopolishSkill(base.SkillBase):
    software = "nanopolish"
    binary = "nanopolish"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        binary = self._resolve_binary()
        cmd: list[str] = [binary, subcommand]
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "index":
            for d in _as_list(kw.get("fast5_dir")):
                cmd += ["-d", d]
            f5 = kw.get("fast5_file")
            if f5:
                cmd += ["-f", str(f5)]
            moves = kw.get("moves")
            if moves:
                cmd += ["-m", str(moves)]
            summary = kw.get("summary")
            if summary:
                cmd += ["-s", str(summary)]
            reads = _as_list(kw.get("reads")) or _as_list(kw.get("input"))
            if not reads:
                raise ValueError("index 需要 reads（位置参数，fastq/fasta，可多个）")
            cmd += reads

        elif subcommand == "variants":
            if kw.get("consensus"):
                cmd.append("--consensus")
            out = kw.get("output") or kw.get("outfile")
            if out:
                cmd += ["-o", str(out)]
            window = kw.get("window")
            if window:
                cmd += ["-w", str(window)]
            reads = kw.get("reads") or kw.get("input")
            if reads:
                cmd += ["-r", str(reads)]
            bam = kw.get("bam")
            if bam:
                cmd += ["-b", str(bam)]
            genome = kw.get("genome")
            if genome:
                cmd += ["-g", str(genome)]
            ma = kw.get("methylation_aware")
            if ma:
                cmd.append(f"--methylation-aware={ma}")
            cmd += ["-t", str(threads)]

        elif subcommand == "vcf2fasta":
            genome = kw.get("genome")
            if genome:
                cmd += ["-g", str(genome)]
            fai = kw.get("fai")
            if fai:
                cmd += ["-f", str(fai)]
            if kw.get("methylation"):
                cmd.append("--methylation")
            vcf = kw.get("vcf") or kw.get("input")
            if not vcf:
                raise ValueError("vcf2fasta 需要 VCF（位置参数）")
            cmd.append(str(vcf))

        elif subcommand == "methylation":
            reads = kw.get("reads") or kw.get("input")
            if reads:
                cmd += ["-r", str(reads)]
            bam = kw.get("bam")
            if bam:
                cmd += ["-b", str(bam)]
            genome = kw.get("genome")
            if genome:
                cmd += ["-g", str(genome)]
            window = kw.get("window")
            if window:
                cmd += ["-w", str(window)]
            out = kw.get("output")
            if out:
                cmd += ["-o", str(out)]
            cmd += ["-t", str(threads)]

        elif subcommand == "eventalign":
            reads = kw.get("reads") or kw.get("input")
            if reads:
                cmd += ["-r", str(reads)]
            bam = kw.get("bam")
            if bam:
                cmd += ["-b", str(bam)]
            genome = kw.get("genome")
            if genome:
                cmd += ["-g", str(genome)]
            if kw.get("scale_events"):
                cmd.append("--scale-events")
            out = kw.get("output")
            if out:
                cmd += ["-o", str(out)]
            cmd += ["-t", str(threads)]

        elif subcommand == "phase-reads":
            bam = kw.get("bam")
            vcf = kw.get("vcf")
            if not bam or not vcf:
                raise ValueError("phase-reads 需要 <bam> 与 <vcf>（位置参数）")
            cmd += [str(bam), str(vcf)]
            cmd += ["-t", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_io_opts(p: argparse.ArgumentParser, reads: bool = True, bam: bool = True,
                 genome: bool = True, out: bool = True, window: bool = True) -> None:
    if reads:
        p.add_argument("-r", "--reads", help="Nanopore reads（fastq/fasta）")
    if bam:
        p.add_argument("-b", "--bam", help="比对 BAM（已排序+索引）")
    if genome:
        p.add_argument("-g", "--genome", help="参考基因组 FASTA")
    if out:
        p.add_argument("-o", "--output", help="输出文件")
    if window:
        p.add_argument("-w", "--window", help="处理区域（如 tig00000001:1-100000）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="nanopolish-skill",
        description="nanopolish native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("reads", nargs="+", help="reads 文件（fastq/fasta，可多个）")
    pi.add_argument("-d", "--fast5-dir", dest="fast5_dir", action="append",
                    help="fast5 目录（-d，可重复）")
    pi.add_argument("-f", "--fast5-file", dest="fast5_file", help="单个 fast5 文件")
    pi.add_argument("-m", "--moves", help="moves 文件")
    pi.add_argument("-s", "--summary", help="sequencing_summary 文件")
    _add_runtime_opts(pi)

    # variants
    pv = sub.add_parser("variants", help=SUBCOMMANDS["variants"])
    _add_io_opts(pv)
    pv.add_argument("--outfile", help="-o 的别名（输出 VCF）")
    pv.add_argument("--consensus", action="store_true", help="生成一致性序列")
    pv.add_argument("--methylation-aware", dest="methylation_aware",
                    help="甲基化感知类型（如 dcm,dam）")
    pv.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pv)

    # vcf2fasta
    pf = sub.add_parser("vcf2fasta", help=SUBCOMMANDS["vcf2fasta"])
    pf.add_argument("vcf", nargs="?", help="输入 VCF")
    pf.add_argument("-g", "--genome", help="参考基因组 FASTA")
    pf.add_argument("-f", "--fai", help="参考 FASTA 的 .fai 索引")
    pf.add_argument("--methylation", nargs="?", const=True,
                    help="同时输出甲基化调用（可带输出前缀）")
    _add_runtime_opts(pf)

    # methylation
    pm = sub.add_parser("methylation", help=SUBCOMMANDS["methylation"])
    _add_io_opts(pm)
    _add_runtime_opts(pm)

    # eventalign
    pe = sub.add_parser("eventalign", help=SUBCOMMANDS["eventalign"])
    _add_io_opts(pe)
    pe.add_argument("--scale-events", dest="scale_events", action="store_true",
                    help="对事件信号做缩放")
    _add_runtime_opts(pe)

    # phase-reads
    pp = sub.add_parser("phase-reads", help=SUBCOMMANDS["phase-reads"])
    pp.add_argument("bam", help="比对 BAM")
    pp.add_argument("vcf", help="变异 VCF")
    _add_runtime_opts(pp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = NanopolishSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = NanopolishSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

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
