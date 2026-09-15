#!/usr/bin/env python3
"""freebayes native 标准入口驱动（命令行工具）。

freebayes 的典型调用（官方 / 文档 07 §7）：
    freebayes -f genome.fasta V1.bam > variants.vcf
    freebayes -f genome.fasta V1.bam V2.bam > variants.multi.vcf
    freebayes -f genome.fasta --ploidy 1 V1.bam > variants.haploid.vcf
    freebayes -f genome.fasta --min-alternate-count 3 --min-coverage 5 V1.bam > filtered.vcf
    freebayes-parallel <(fasta_generate_regions.py ref.fa.fai 100000) 36 -f ref.fa aln.bam > out.vcf
conda（bioconda::freebayes）提供 `freebayes` 与 `freebayes-parallel` 两个命令。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py call -f genome.fasta --min-alternate-count 3 --min-coverage 5 \\
       --ploidy 2 -o variants.vcf V1.bam V2.bam
   python main.py parallel regions.bed -f genome.fasta -o out.vcf V1.bam --threads 8
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- call 为单线程；parallel 走 freebayes-parallel，把 --threads（默认 8）作为并发 CPU 数。
- VCF 写 stdout，由 main() 在给出 --output 时落盘（对齐文档重定向用法，可直连 bcftools）。
- 临时目录经 TMPDIR 注入。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "call": "单/多样本贝叶斯变异检测（freebayes；BAM -> VCF）",
    "parallel": "按区域文件并行检测（freebayes-parallel，GNU parallel）",
}

# 子命令 -> 真实可执行名
_BIN_FOR = {
    "call": "freebayes",
    "parallel": "freebayes-parallel",
}


class FreebayesSkill(base.SkillBase):
    software = "freebayes"
    binary = "freebayes"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令可执行名（freebayes / freebayes-parallel）惰性解析。"""
        bin_name = name or self.binary
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 freebayes。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        bin_name = _BIN_FOR[subcommand]
        cmd: list[str] = [self._resolve_binary(bin_name)]

        # parallel：先区域文件 + 并发 CPU 数（freebayes-parallel 的位置参数）
        if subcommand == "parallel":
            regions = kw.get("regions")
            if not regions:
                raise ValueError("parallel 缺少必填参数 regions（区域文件，如 regions.bed）")
            cmd.append(str(regions))
            cmd.append(str(self._effective_threads(subcommand, kw.get("threads"))))

        # 参考基因组
        ref = kw.get("reference")
        if not ref:
            raise ValueError(f"{subcommand} 缺少必填参数 reference（-f 参考 FASTA）")
        cmd += ["-f", str(ref)]

        # 倍性
        if kw.get("ploidy") is not None:
            cmd += ["--ploidy", str(kw["ploidy"])]
        # 过滤阈值
        thresholds = [
            ("min_alternate_count", "--min-alternate-count"),
            ("min_coverage", "--min-coverage"),
            ("min_base_quality", "--min-base-quality"),
            ("min_mapping_quality", "--min-mapping-quality"),
            ("min_alternate_fraction", "--min-alternate-fraction"),
        ]
        for key, flag in thresholds:
            if kw.get(key) is not None:
                cmd += [flag, str(kw[key])]
        # 区域 / targets
        if kw.get("region"):
            cmd += ["-r", str(kw["region"])]
        if kw.get("targets"):
            cmd += ["-t", str(kw["targets"])]
        # BAM 列表
        if kw.get("bam_list"):
            cmd += ["--bam-list", str(kw["bam_list"])]
        # 输出模式
        if kw.get("gvcf"):
            cmd.append("--gvcf")
        if kw.get("genotype_qualities"):
            cmd.append("--genotype-qualities")

        # 输入 BAM（位置参数，可多个；call/parallel 均支持）
        bams = kw.get("bams") or kw.get("input")
        if bams:
            items = bams if isinstance(bams, list) else [bams]
            cmd += [str(b) for b in items]
        elif not kw.get("bam_list"):
            raise ValueError(f"{subcommand} 缺少输入：位置 BAM/CRAM 或 --bam-list")

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（parallel 的并发 CPU 数）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="freebayes-skill",
        description="freebayes native 技能驱动（贝叶斯变异检测；输出 VCF）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _common(pp: argparse.ArgumentParser) -> None:
        pp.add_argument("-f", "--reference", help="参考基因组 FASTA（须 .fai）")
        pp.add_argument("--ploidy", type=int, help="样本倍性（默认 2）")
        pp.add_argument("--min-alternate-count", dest="min_alternate_count", type=int, help="最小等位计数")
        pp.add_argument("--min-coverage", dest="min_coverage", type=int, help="最小覆盖深度")
        pp.add_argument("--min-base-quality", dest="min_base_quality", type=int, help="最小碱基质量")
        pp.add_argument("--min-mapping-quality", dest="min_mapping_quality", type=int, help="最小比对质量")
        pp.add_argument("--min-alternate-fraction", dest="min_alternate_fraction", type=float, help="最小等位比例")
        pp.add_argument("-r", "--region", help="仅分析指定区域（chr:start-end）")
        pp.add_argument("-t", "--targets", help="仅分析 targets BED 区域")
        pp.add_argument("--bam-list", dest="bam_list", help="BAM 列表文件（与位置 BAM 二选一）")
        pp.add_argument("--gvcf", action="store_true", help="输出 gVCF")
        pp.add_argument("--genotype-qualities", dest="genotype_qualities", action="store_true", help="输出基因型质量")
        pp.add_argument("-o", "--output", help="输出 VCF 文件（stdout 落盘）")
        pp.add_argument("--extra-args", help="透传给 freebayes 的额外参数")
        _add_runtime_opts(pp)

    pc = sub.add_parser("call", help=SUBCOMMANDS["call"])
    pc.add_argument("bams", nargs="*", help="输入 BAM/CRAM（可多个）")
    _common(pc)

    pp = sub.add_parser("parallel", help=SUBCOMMANDS["parallel"])
    pp.add_argument("regions", help="区域文件（bed；fasta_generate_regions.py 生成）")
    pp.add_argument("bams", nargs="*", help="输入 BAM/CRAM（可多个）")
    _common(pp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = FreebayesSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FreebayesSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "output") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # freebayes 写 VCF 到 stdout，给出 --output 时落盘
    if getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
