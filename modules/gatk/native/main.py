#!/usr/bin/env python3
"""gatk native 标准入口驱动（Java CLI 驱动）。

GATK v4 是 Java 程序，官方 zip 内含 `gatk` launcher，CLI 形如：
    gatk HaplotypeCaller -I in.bam -R ref.fa -O out.g.vcf.gz [-ERC GVCF]
    gatk GenotypeGVCFs -V cohort.g.vcf.gz -R ref.fa -O out.vcf.gz
    gatk BaseRecalibrator -I in.bam -R ref.fa -O recal.table --known-sites dbsnp.vcf.gz
conda（gatk4/gatk4-main）/ biocontainer 提供同一 `gatk` launcher（内部仍调 java）。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：子命令用**小写**工具名，自动映射真实 GATK 工具名：
   python main.py haplotypecaller -I sample.bam -R hg38.fa -O sample.g.vcf.gz --erc GVCF
   python main.py genotypegvcfs -V cohort.g.vcf.gz -R hg38.fa -O cohort.vcf.gz
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位入口：优先 PATH 上 `gatk`（bioconda/biocontainer wrapper）；否则 GATK_JAR
  环境变量 → conda share / ~/software 常见位置 gatk-package-*-local.jar，
  以 `java -jar` 调用（需宿主 java 17）。
- HaplotypeCaller 自动注入 --native-pair-hmm-threads（默认 4）。
- JVM 堆内存与临时目录经 JAVA_TOOL_OPTIONS / TMPDIR 注入（JVM 自动读取）。
- --dry-run 仅构造并打印 argv（不执行），供降级 argv 构造回归。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shlex
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令（小写） -> 真实 GATK 工具名
SUBCOMMANDS = {
    "haplotypecaller": "HaplotypeCaller：胚系短变异检测（-ERC GVCF 输出 gVCF）",
    "genotypegvcfs": "GenotypeGVCFs：联合 gVCF 基因分型 -> VCF",
    "combinegvcfs": "CombineGVCFs：合并多个 gVCF（-V 可重复）",
    "variantfiltration": "VariantFiltration：硬过滤（--filter-expression/--filter-name）",
    "selectvariants": "SelectVariants：按类型/区间选择变异",
    "baserecalibrator": "BaseRecalibrator：BQSR 校正表构建（--known-sites 可重复）",
    "applybqsr": "ApplyBQSR：应用 BQSR 校正表到 BAM",
    "splitncigarreads": "SplitNCigarReads：RNA-seq N-CIGAR 拆分",
}

_JAR_GLOBS = [
    "GATK_JAR",  # 环境变量（绝对路径）
    "{conda}/share/gatk4*/gatk-package-*-local.jar",
    "~/software/gatk-*/gatk-package-*-local.jar",
    "~/software/gatk*/gatk-package-*-local.jar",
]

def _expand_jar_candidates() -> list[str]:
    cands: list[str] = []
    env_jar = os.environ.get("GATK_JAR")
    if env_jar:
        cands.append(env_jar)
    conda = os.environ.get("CONDA_PREFIX", "")
    for pat in _JAR_GLOBS[1:]:
        p = pat.format(conda=conda)
        if p.startswith("~"):
            p = str(Path(p).expanduser())
        cands.append(p)
    return cands


class GatkSkill(base.SkillBase):
    software = "gatk"
    binary = "gatk"

    def _locate_jar(self) -> str | None:
        for c in _expand_jar_candidates():
            hits = sorted(glob.glob(c))
            if hits:
                return hits[0]
        return None

    def _resolve_launcher(self, dry_run: bool = False) -> list[str] | None:
        """返回命令前缀：['gatk'] 或 ['java','-jar',jar]；dry_run 给占位名。"""
        if dry_run:
            return [self.binary]
        wrapper = base.which("gatk")
        if wrapper:
            return [wrapper]
        jar = self._locate_jar()
        if jar:
            java = base.which("java")
            if not java:
                raise RuntimeError(
                    "已定位 gatk jar 但 PATH 中无 java；请先安装 Java 17 "
                    "（conda: mamba install -n <env> -c conda-forge openjdk）"
                )
            return [java, "-jar", jar]
        return None

    def _tool(self, subcommand: str) -> str:
        return SUBCOMMANDS[subcommand].split("：")[0]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        launcher = self._resolve_launcher(bool(kw.get("dry_run")))
        if launcher is None:
            raise RuntimeError(
                "未找到 gatk launcher 或 gatk-package-*.jar；请先安装：conda/mamba"
                "（bioconda::gatk4 / gatk4-main）、brewsci/bio gatk 或官方 zip"
                "（export GATK_JAR=/path/to/gatk-package-4.7.0.0-local.jar）"
            )
        cmd: list[str] = list(launcher)
        cmd.append(self._tool(subcommand))
        extra_tokens = str(kw.get("extra_args") or "").split()

        # -R 参考（除 variantfiltration/selectvariants 外均作为常规项传入）
        ref = kw.get("reference")
        if ref:
            cmd += ["-R", str(ref)]

        if subcommand == "haplotypecaller":
            self._add_input(cmd, kw)
            cmd += ["-O", str(kw.get("output") or "out.g.vcf.gz")]
            erc = kw.get("erc")
            if erc:
                cmd += ["--emit-ref-confidence", str(erc).upper()]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--native-pair-hmm-threads", str(threads)]
            if kw.get("interval"):
                cmd += ["-L", str(kw["interval"])]
        elif subcommand in ("genotypegvcfs", "variantfiltration", "selectvariants"):
            vcf = kw.get("variant") or kw.get("input")
            if not vcf:
                raise ValueError(f"{subcommand} 缺少必填参数 variant（-V VCF/GVCF）")
            cmd += ["-V", str(vcf)]
            cmd += ["-O", str(kw.get("output") or "out.vcf.gz")]
            if subcommand == "variantfiltration":
                fe = kw.get("filter_expression")
                fn = kw.get("filter_name")
                if fe or fn:
                    if not (fe and fn):
                        raise ValueError(
                            "variantfiltration 需要同时给出 --filter-expression 与 --filter-name")
                    cmd += ["--filter-expression", str(fe), "--filter-name", str(fn)]
            elif subcommand == "selectvariants":
                st = kw.get("select_type")
                if st:
                    types = st if isinstance(st, list) else [st]
                    for t in types:
                        cmd += ["--select-type", str(t)]
        elif subcommand == "combinegvcfs":
            vcfs = kw.get("variants") or ([kw["variant"]] if kw.get("variant") else None)
            if not vcfs:
                raise ValueError("combinegvcfs 至少需要 1 个 -V GVCF 输入")
            items = vcfs if isinstance(vcfs, list) else [vcfs]
            for v in items:
                cmd += ["-V", str(v)]
            cmd += ["-O", str(kw.get("output") or "cohort.g.vcf.gz")]
        elif subcommand in ("baserecalibrator", "applybqsr", "splitncigarreads"):
            bam = kw.get("input")
            if not bam:
                raise ValueError(f"{subcommand} 缺少必填参数 input（-I BAM）")
            cmd += ["-I", str(bam)]
            if subcommand == "baserecalibrator":
                cmd += ["-O", str(kw.get("output") or "recal.table")]
                ks = kw.get("known_sites")
                if ks:
                    items = ks if isinstance(ks, list) else [ks]
                    for k in items:
                        cmd += ["--known-sites", str(k)]
            elif subcommand == "applybqsr":
                rf = kw.get("recal_file")
                if not rf:
                    raise ValueError("applybqsr 缺少必填参数 recal_file（--bqsr-recal-file）")
                cmd += ["--bqsr-recal-file", str(rf)]
                cmd += ["-O", str(kw.get("output") or "out.bqsr.bam")]
            else:  # splitncigarreads
                cmd += ["-O", str(kw.get("output") or "out.split.bam")]
                if kw.get("interval"):
                    cmd += ["-L", str(kw["interval"])]

        cmd += extra_tokens
        return cmd

    def _add_input(self, cmd: list[str], kw: dict) -> None:
        inp = kw.get("input")
        if not inp:
            raise ValueError("缺少必填参数 input（-I BAM）")
        cmd += ["-I", str(inp)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（HaplotypeCaller pair-HMM）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")
    p.add_argument("--extra-args", dest="extra_args", help="透传额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gatk-skill",
        description="gatk native 技能驱动（GATK4 工具；JVM 堆内存经 JAVA_TOOL_OPTIONS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # -I 型工具（BAM 输入）
    for name in ("haplotypecaller", "baserecalibrator", "applybqsr", "splitncigarreads"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("-I", "--input", help="输入 BAM/CRAM")
        ps.add_argument("-R", "--reference", help="参考 FASTA（须 .dict + .fai）")
        ps.add_argument("-O", "--output", help="输出文件")
        if name == "haplotypecaller":
            ps.add_argument("--erc", choices=["NONE", "BP_RESOLUTION", "GVCF",
                                              "none", "bp_resolution", "gvcf"],
                            help="--emit-ref-confidence 输出模式（GVCF 用于 cohort）")
            ps.add_argument("-L", "--interval", help="区间")
        elif name == "baserecalibrator":
            ps.add_argument("--known-sites", dest="known_sites", action="append",
                            help="已知变异位点 VCF（可重复）")
        elif name == "applybqsr":
            ps.add_argument("--bqsr-recal-file", dest="recal_file", help="BQSR 校正表")
        else:  # splitncigarreads
            ps.add_argument("-L", "--interval", help="区间")
        _add_runtime_opts(ps)

    # -V 型工具（VCF/GVCF 输入）
    for name in ("genotypegvcfs", "variantfiltration", "selectvariants"):
        pv = sub.add_parser(name, help=SUBCOMMANDS[name])
        pv.add_argument("-V", "--variant", help="输入 VCF/GVCF")
        pv.add_argument("-R", "--reference", help="参考 FASTA")
        pv.add_argument("-O", "--output", help="输出 VCF")
        if name == "variantfiltration":
            pv.add_argument("--filter-expression", dest="filter_expression", help="过滤表达式（如 'QD < 2.0'）")
            pv.add_argument("--filter-name", dest="filter_name", help="过滤名")
        elif name == "selectvariants":
            pv.add_argument("--select-type", dest="select_type", action="append",
                            help="选择类型 SNP/INDEL/MIXED/MNP/…（可重复）")
        _add_runtime_opts(pv)

    pc = sub.add_parser("combinegvcfs", help=SUBCOMMANDS["combinegvcfs"])
    pc.add_argument("-V", "--variant", dest="variants", action="append", help="输入 gVCF（可重复）")
    pc.add_argument("-R", "--reference", help="参考 FASTA")
    pc.add_argument("-O", "--output", help="合并输出 gVCF")
    _add_runtime_opts(pc)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:22s}  {v}")
        return 0
    if "--schema" in args:
        skill = GatkSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GatkSkill()
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
