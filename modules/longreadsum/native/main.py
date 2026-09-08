#!/usr/bin/env python3
"""longreadsum native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py bam -i aln.bam -o qc_out --threads 8
   python main.py fq -P "reads/*.fastq" -o qc_fq -Q QC_
   python main.py fa -i reads.fa -o qc_fa
   python main.py rrms -i rrms.bam -c decisions.csv -o qc_rrms
   python main.py pod5 -i reads.pod5 --basecalls basecalls.bam -o qc_pod5
   python main.py f5s -i reads.fast5 -R 5 -o qc_f5s
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py <sub> ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑（LongReadSum v1.6.0 官方 CLI；参见 WGLab/LongReadSum README）：
  longreadsum <FILETYPE> -i <input> -o <outdir> [-t threads] [-Q prefix] [-s sample] ...
  FILETYPE: fa | fq | f5 | f5s | pod5 | seqtxt | bam | rrms
  输入三选一：-i 单文件 / -I 逗号多文件 / -P 通配符模式；
  公共参数：-o/--outputfolder、-t/--threads、-Q/--outprefix、-s/--sample、-g/--log、-G/--log-level；
  输出：HTML 报告 + JSON summary（v1.6.0，MultiQC --module longreadsum 兼容）。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令（filetype）语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "bam": "BAM/CRAM 比对 QC（WGS；--mod 碱基修饰分析；--genebed 时算 RNA-seq TIN 分数）",
    "rrms": "RRMS BAM 按 -c CSV 拆分 accepted/rejected reads 并出 QC",
    "pod5": "ONT POD5 信号 QC（-b/--basecalls 传带 move 表的 basecalled BAM 做信号-碱基对应）",
    "f5s": "ONT FAST5 信号统计 QC（-r read ID 列表 / -R 随机抽样数）",
    "f5": "ONT FAST5 序列 QC",
    "seqtxt": "ONT basecall summary（sequencing_summary.txt）QC",
    "fq": "FASTQ QC（-u/--udqual 质量偏移，默认 33）",
    "fa": "FASTA QC",
}

# 各 filetype 特有参数映射（argparse dest → longreadsum flag，None 表示不注入由调用方处理）
_SPECIAL_FLAGS = {
    "rrms": [("csv", "-c")],
    "pod5": [("basecalls", "-b"), ("read_ids", "-r"), ("read_count", "-R")],
    "f5s": [("read_ids", "-r"), ("read_count", "-R")],
    "bam": [("modprob", "--modprob"), ("ref", "--ref"),
            ("genebed", "--genebed"), ("sample_size", "--sample-size"),
            ("min_coverage", "--min-coverage")],
    "fq": [("udqual", "-u")],
}


class LongreadsumSkill(base.SkillBase):
    software = "longreadsum"
    binary = "longreadsum"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 longreadsum 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = [binary, subcommand]
        # 输入三选一：-i 单文件 > -I 逗号多文件 > -P 通配符
        if kw.get("input"):
            cmd += ["-i", str(kw["input"])]
        elif kw.get("inputs"):
            cmd += ["-I", str(kw["inputs"])]
        elif kw.get("pattern"):
            cmd += ["-P", str(kw["pattern"])]
        else:
            raise ValueError(f"{subcommand} 需要输入：--input（单文件）/ --inputs（逗号多文件）/ --pattern（通配符）")

        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        if kw.get("prefix"):
            cmd += ["-Q", str(kw["prefix"])]
        if kw.get("sample"):
            cmd += ["-s", str(kw["sample"])]
        if kw.get("log"):
            cmd += ["-g", str(kw["log"])]
        if kw.get("log_level") is not None:
            cmd += ["-G", str(kw["log_level"])]
        cmd += ["-t", str(threads)]

        # filetype 特有参数
        for dest, flag in _SPECIAL_FLAGS.get(subcommand, []):
            val = kw.get(dest)
            if val is None:
                continue
            if dest == "modprob":
                cmd += [flag, str(float(val))]
            else:
                cmd += [flag, str(val)]

        # bam 的 --mod 布尔开关（仅置真时传；v1.6.0 默认 False）
        if subcommand == "bam" and kw.get("mod"):
            cmd.append("--mod")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """公共输入/输出参数（对应官方 set_file_parser_defaults 子集）。"""
    p.add_argument("-i", "--input", help="单个输入文件（FASTA/FASTQ/BAM/FAST5/POD5/summary.txt）")
    p.add_argument("-I", "--inputs", help="多个逗号分隔的输入文件路径")
    p.add_argument("-P", "--pattern", help='通配符模式匹配多个输入（引号包裹，如 "dir/*.fast5"）')
    p.add_argument("-o", "--output", metavar="OUTDIR", help="输出目录（默认官方 output_LongReadSum）")
    p.add_argument("-Q", "--prefix", help="输出文件名前缀（默认 QC_）")
    p.add_argument("-s", "--sample", help="样本名（默认 Sample）")
    p.add_argument("-g", "--log", help="日志文件路径（默认 log_output.log）")
    p.add_argument("-G", "--log-level", type=int, help="日志级别 1:DEBUG..5:CRITICAL（默认 2）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="longreadsum-skill",
        description="longreadsum native 技能驱动（bam/rrms/pod5/f5s/f5/seqtxt/fq/fa 长读 QC；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<filetype>")

    # 8 个 filetype 子命令：fa / fq / f5 / f5s / pod5 / seqtxt / bam / rrms
    pc = sub.add_parser("bam", help=SUBCOMMANDS["bam"])
    _add_common_opts(pc)
    pc.add_argument("--mod", action="store_true", help="运行碱基修饰（MM/ML）分析")
    pc.add_argument("--modprob", type=float, help="碱基修饰过滤阈值（默认 0.5）")
    pc.add_argument("--ref", help="参考基因组 FASTA（--mod 识别 CpG 用）")
    pc.add_argument("--genebed", help="Gene BED12 文件（RNA-seq BAM 算 TIN 分数）")
    pc.add_argument("--sample-size", type=int, help="TIN 抽样数（默认 100）")
    pc.add_argument("--min-coverage", type=int, help="TIN 最小覆盖度（默认 10）")
    pc.add_argument("--extra-args", help="透传给 longreadsum 的额外参数")
    _add_runtime_opts(pc)

    pr = sub.add_parser("rrms", help=SUBCOMMANDS["rrms"])
    _add_common_opts(pr)
    pr.add_argument("-c", "--csv", help="RRMS 决策 CSV（read_id / decision 列）")
    pr.add_argument("--extra-args", help="透传给 longreadsum 的额外参数")
    _add_runtime_opts(pr)

    pp = sub.add_parser("pod5", help=SUBCOMMANDS["pod5"])
    _add_common_opts(pp)
    pp.add_argument("-b", "--basecalls", help="带 move 表的 basecalled BAM（dorado --emit-moves）")
    pp.add_argument("-r", "--read-ids", dest="read_ids", help="逗号分隔的 read ID 列表")
    pp.add_argument("-R", "--read-count", dest="read_count", type=int, help="随机抽样 read 数（默认 3）")
    pp.add_argument("--extra-args", help="透传给 longreadsum 的额外参数")
    _add_runtime_opts(pp)

    pf = sub.add_parser("f5s", help=SUBCOMMANDS["f5s"])
    _add_common_opts(pf)
    pf.add_argument("-r", "--read-ids", dest="read_ids", help="逗号分隔的 read ID 列表")
    pf.add_argument("-R", "--read-count", dest="read_count", type=int, help="随机抽样 read 数（默认 3）")
    pf.add_argument("--extra-args", help="透传给 longreadsum 的额外参数")
    _add_runtime_opts(pf)

    for name in ("f5", "seqtxt", "fq", "fa"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        _add_common_opts(ps)
        if name == "fq":
            ps.add_argument("-u", "--udqual", type=int, help="FASTQ 质量偏移（默认 33）")
        ps.add_argument("--extra-args", help="透传给 longreadsum 的额外参数")
        _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射到 longreadsum -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = LongreadsumSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LongreadsumSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    if dry_run:
        # --dry-run 只做命令构建自检，不要求真实二进制已安装
        skill._resolve_binary = lambda: "longreadsum"

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
        return 0

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
