#!/usr/bin/env python3
"""hisat2 native 标准入口驱动。

HISAT2 是 C 程序（graph FM-index 剪接比对器），CLI 形如：
    hisat2-build [-p N] [--ss ss.txt] [--exon exons.txt] <ref.fa> <ht2-base>
    hisat2 [-p N] [--dta] [--rna-strandness RF] -x <ht2-base> -1 R1.fq [-2 R2.fq|-U se.fq]
conda / brew / biocontainer 提供 hisat2 与 hisat2-build 两个可执行。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py index genome.fa --index-base hg38 --ss ss.txt --threads 16
   python main.py align -x hg38 -1 s_R1.fq.gz -2 s_R2.fq.gz --dta \
       --rna-strandness RF --threads 16 -S out.sam
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位可执行：align 用 `hisat2`、index 用 `hisat2-build`（bioconda / brew / 官方 make 产物均可）。
- -p 线程自动注入（默认 8，可 --threads 覆盖）；TMPDIR 经 env 注入。
- align 的 SAM 输出走 stdout（原生），也可 -S 落盘。
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
    "index": "建索引：hisat2-build <ref.fa> <base>（生成 .1.ht2… 族；可加 --ss/--exon）",
    "align": "比对：hisat2 -x <base> -1 R1 [-2 R2|-U se]（--dta/--rna-strandness；SAM 输出）",
}

# 子命令 -> 实际二进制名
_SUB_BIN = {
    "index": "hisat2-build",
    "align": "hisat2",
}


class Hisat2Skill(base.SkillBase):
    software = "hisat2"
    binary = "hisat2"

    def _resolve_bin(self, subcommand: str, dry_run: bool = False) -> str:
        bin_name = _SUB_BIN[subcommand]
        if dry_run:
            return bin_name
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先安装：conda/mamba（bioconda::hisat2=2.2.3）、"
                "brew（brewsci/bio hisat2）、官方源码 make 或 quay.io/biocontainers/hisat2 镜像"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_bin(subcommand, bool(kw.get("dry_run")))
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd: list[str] = [bin_path]
        extra_tokens = str(kw.get("extra_args") or "").split()

        if subcommand == "index":
            ref = kw.get("reference")
            index_base = kw.get("index_base")
            if not ref or not index_base:
                raise ValueError("index 缺少必填参数 reference（FASTA）与 index_base（输出 basename）")
            cmd += ["-p", str(threads)]
            if kw.get("splice_sites"):
                cmd += ["--ss", str(kw["splice_sites"])]
            if kw.get("exons"):
                cmd += ["--exon", str(kw["exons"])]
            cmd += extra_tokens
            cmd.append(str(ref))
            cmd.append(str(index_base))
            return cmd

        # align
        idx = kw.get("index")
        if not idx:
            raise ValueError("align 缺少必填参数 index（-x HT2 索引 basename）")
        reads1 = kw.get("reads1")
        reads2 = kw.get("reads2")
        reads = kw.get("reads")
        if not (reads1 or reads):
            raise ValueError("align 缺少 reads 输入（--reads1/-1 双端或 --reads/-U 单端）")
        cmd += ["-p", str(threads)]
        if kw.get("dta"):
            cmd.append("--dta")
        if kw.get("rna_strandness"):
            cmd += ["--rna-strandness", str(kw["rna_strandness"])]
        cmd += ["-x", str(idx)]
        if reads1:
            cmd += ["-1", str(reads1)]
            if reads2:
                cmd += ["-2", str(reads2)]
            else:
                raise ValueError("align 给了 --reads1 但缺 --reads2（双端需成对；单端请用 --reads/-U）")
        elif reads:
            cmd += ["-U", str(reads)]
        if kw.get("output"):
            cmd += ["-S", str(kw["output"])]
        cmd += extra_tokens
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（index/align 默认 8）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")
    p.add_argument("--extra-args", dest="extra_args", help="透传额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hisat2-skill",
        description="hisat2 native 技能驱动（RNA-seq 剪接比对；-p 线程 / TMPDIR 自动优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("reference", help="参考序列 FASTA（可逗号分隔多文件）")
    pi.add_argument("--index-base", dest="index_base", required=True, help="输出索引 basename")
    pi.add_argument("--ss", "--splice-sites", dest="splice_sites", help="剪接位点文件")
    pi.add_argument("--exon", "--exons", dest="exons", help="外显子文件")
    _add_runtime_opts(pi)

    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("-x", "--index", required=True, help="HT2 索引 basename（不含 .1.ht2）")
    pa.add_argument("-1", "--reads1", help="mate1 reads（FASTQ/FASTA，可 .gz/逗号多文件）")
    pa.add_argument("-2", "--reads2", help="mate2 reads（双端；与 -1 成对）")
    pa.add_argument("-U", "--reads", help="单端 reads（无双端时）")
    pa.add_argument("-S", "--output", help="SAM 输出文件（缺省 stdout）")
    pa.add_argument("--dta", action="store_true", help="输出兼容转录本组装（stringtie）")
    pa.add_argument("--rna-strandness", dest="rna_strandness",
                    choices=["FR", "RF", "unstranded"], help="链特异性文库类型")
    _add_runtime_opts(pa)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:6s}  {v}")
        return 0
    if "--schema" in args:
        skill = Hisat2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Hisat2Skill()
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
