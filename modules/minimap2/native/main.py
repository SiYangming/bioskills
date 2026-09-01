#!/usr/bin/env python3
"""minimap2 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align --reads reads.fa --reference refs.fa --outdir out --prefix sample --threads 8
   python main.py align --reads reads.fa --reference refs.fa --outdir out --bam --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py align ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/minimap2_align.py：
  BAM： minimap2 [args] -t N [-c] [-L] -a <ref> <reads> | samtools sort -@ N | samtools view -@ N -b -h -o out.bam
  PAF： minimap2 [args] -t N [-c] [-L] <ref> <reads> -o out.paf
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "align": "reads -> 参考基因组比对，输出 PAF 或 BAM（BAM 走 samtools sort/view 管线）",
}


def _strip_ext(path_str: str) -> str:
    """去除常见 fasta/fastq 扩展名（含 gz），返回不带扩展的文件基名。"""
    base_name = os.path.basename(path_str)
    for suf in (".fa.gz", ".fasta.gz", ".fastq.gz", ".fa", ".fasta", ".fastq"):
        if base_name.endswith(suf):
            return base_name[: -len(suf)]
    return os.path.splitext(base_name)[0]


class Minimap2Skill(base.SkillBase):
    software = "minimap2"
    binary = "minimap2"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 minimap2 命令行。"""
        if subcommand != "align":
            raise ValueError(f"不支持的子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        return self._build_align(kw)

    def _build_align(self, kw: dict) -> list[str]:
        mm2 = self._resolve_binary()
        samtools = (
            os.path.expanduser(kw["samtools_bin"])
            if kw.get("samtools_bin")
            else (base.which("samtools") or "samtools")
        )
        reads = kw.get("reads")
        if not reads:
            raise ValueError("align 需要输入 reads（--reads）")
        ref = kw.get("reference")

        outdir = Path(kw.get("outdir") or ".")
        outdir.mkdir(parents=True, exist_ok=True)
        prefix = kw.get("prefix") or _strip_ext(str(reads))
        out_prefix = outdir / prefix

        threads = self._effective_threads("align", kw.get("threads"))
        args = kw.get("args") or ""
        bam = bool(kw.get("bam"))
        cigarpaf = "-c" if (kw.get("cigar_paf") and not bam) else ""
        set_cigar_bam = "-L" if (kw.get("cigar_bam") and bam) else ""
        ref_arg = str(ref) if ref else str(reads)  # 无参考时退化为 reads vs reads

        q = shlex.quote
        if bam:
            # 与 nf-core minimap2/align 保持一致：-a | samtools sort | samtools view -b -h -o
            cmd_str = (
                f"{q(mm2)} {args} -t {threads} {q(ref_arg)} {q(str(reads))} "
                f"{cigarpaf} {set_cigar_bam} -a | "
                f"{q(samtools)} sort -@ {threads} | "
                f"{q(samtools)} view -@ {threads} -b -h -o {q(str(out_prefix))}.bam"
            )
            return ["bash", "-o", "pipefail", "-c", cmd_str]
        else:
            cmd: list[str] = [mm2]
            if args:
                cmd += shlex.split(args)
            cmd += ["-t", str(threads)]
            if cigarpaf:
                cmd.append("-c")
            if set_cigar_bam:
                cmd.append("-L")
            cmd += [ref_arg, str(reads), "-o", f"{out_prefix}.paf"]
            return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="minimap2-skill",
        description="minimap2 native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("--reads", required=True, help="输入 FASTA/FASTQ（支持 .gz）")
    pa.add_argument("--reference", default=None, help="参考基因组 FASTA（缺省为 reads vs reads）")
    pa.add_argument("--outdir", default=".", help="输出目录（默认当前目录）")
    pa.add_argument("--prefix", default=None, help="输出前缀（默认从 reads 文件名推断）")
    pa.add_argument("--bam", action="store_true", help="输出 BAM（否则输出 PAF）")
    pa.add_argument("--cigar-paf", action="store_true", help="PAF 输出写入 CIGAR（-c）")
    pa.add_argument("--cigar-bam", action="store_true", help="BAM 输出为长 CIGAR 写 CG 标签（-L）")
    pa.add_argument("--args", default="", help="透传 minimap2 参数（如 \"-x splice -uf -k14\"）")
    pa.add_argument("--samtools-bin", default=None, help="samtools 可执行路径（BAM 管线用）")
    _add_runtime_opts(pa)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Minimap2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Minimap2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

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
