#!/usr/bin/env python3
"""varscan native 标准入口驱动（Java CLI 驱动）。

VarScan 是 Java 程序，官方调用形如：
    java -jar VarScan.jar mpileup2snp V1.mpileup --min-coverage 8 --min-reads2 2 \\
        --min-avg-qual 15 --min-var-freq 0.1 --p-value 0.05 --output-vcf 1 > V1.snp.vcf
    java -jar VarScan.jar somatic paired.mpileup --min-coverage 8 --min-reads2 2 \\
        --min-var-freq 0.05 --somatic-p-value 0.05 --output-vcf 1 somatic_output
conda（bioconda::varscan）提供 `varscan` wrapper（内部仍调 java）；官方 jar 直链
VarScan.v2.4.6.jar，需宿主自备 JRE。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py mpileup2snp V1.mpileup --min-coverage 8 --min-reads2 2 --min-avg-qual 15 \\
       --min-var-freq 0.1 --p-value 0.05 --output-vcf 1 -o V1.snp.vcf
   python main.py somatic paired.mpileup --output-vcf 1 --min-coverage 8 -o somatic_output
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 入口定位：优先 PATH 上 `varscan`（bioconda/biocontainer wrapper）；缺失时用 VARSCAN_JAR
  环境变量 → conda share / ~/software 常见位置的 VarScan.jar，以 `java <JAVA_OPTS> -jar` 调用。
- JVM 堆内存与临时目录经 JAVA_OPTS / TMPDIR 注入（env_vars）。
- mpileup2snp/mpileup2indel/mpileup2cns 写 VCF 到 stdout，由 main() 在给出 --output 时落盘。
- VarScan 单线程；--threads 仅作接口统一。
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

# 子命令语义清单（名称与 VarScan 实际子命令一致，processSomatic 大小写敏感）
SUBCOMMANDS = {
    "mpileup2snp": "从 mpileup 检测 SNP（--output-vcf 1 输出 VCF）",
    "mpileup2indel": "从 mpileup 检测 INDEL",
    "mpileup2cns": "从 mpileup 输出一致性序列（SNP+INDEL 一步）",
    "somatic": "肿瘤-正常配对体细胞变异检测（normal/paired mpileup -> 前缀）",
    "copynumber": "肿瘤-正常配对拷贝数变异分析",
    "processSomatic": "对 somatic 输出做筛选（germline/LOH/somatic 分列）",
    "fpfilter": "基于 BAM 的假阳性过滤（--vcf-file/--bam-file/--output-file）",
}

# stdout 输出型子命令（驱动捕获后落盘）
_STDOUT_SUBCMDS = ("mpileup2snp", "mpileup2indel", "mpileup2cns")

# VarScan.jar 常见候选位置
_JAR_GLOBS = [
    "{conda}/share/varscan*/VarScan.jar",
    "{conda}/share/varscan*/varscan*/VarScan.jar",
    "~/software/varscan*/VarScan.jar",
    "~/software/VarScan*.jar",
]


class VarscanSkill(base.SkillBase):
    software = "varscan"
    binary = "varscan"

    # -- 入口定位 --------------------------------------------------------- #
    def _locate_jar(self) -> str | None:
        env_jar = os.environ.get("VARSCAN_JAR")
        if env_jar and Path(env_jar).exists():
            return env_jar
        conda = os.environ.get("CONDA_PREFIX", "")
        for pat in _JAR_GLOBS:
            p = pat.format(conda=conda)
            if p.startswith("~"):
                p = str(Path(p).expanduser())
            hits = sorted(glob.glob(p))
            if hits:
                return hits[0]
        return None

    def _java_opts(self) -> list[str]:
        return shlex.split(self.env_vars.get("JAVA_OPTS", ""))

    def _launcher(self) -> list[str]:
        """返回命令前缀：['varscan'] 或 ['java', *JAVA_OPTS, '-jar', jar]。"""
        try:
            return [self._resolve_binary()]
        except RuntimeError:
            jar = self._locate_jar()
            if not jar:
                raise RuntimeError(
                    "未找到 varscan：PATH 上无 varscan wrapper，且未定位到 VarScan.jar；"
                    "请 conda/mamba 安装（bioconda::varscan=2.4.6），或下载官方 "
                    "VarScan.v2.4.6.jar 并导出 VARSCAN_JAR=/path/to/VarScan.jar（需宿主 java）"
                )
            java = base.which("java")
            if not java:
                raise RuntimeError(
                    "已定位 VarScan.jar 但 PATH 中无 java；请先安装 JRE（conda: "
                    "mamba install -n <env> -c conda-forge openjdk）"
                )
            return [java, *self._java_opts(), "-jar", jar]

    # -- 通用选项 --------------------------------------------------------- #
    @staticmethod
    def _add_common(cmd: list[str], kw: dict) -> None:
        pairs = [
            ("min_coverage", "--min-coverage"),
            ("min_reads2", "--min-reads2"),
            ("min_avg_qual", "--min-avg-qual"),
            ("min_var_freq", "--min-var-freq"),
            ("min_freq_for_hom", "--min-freq-for-hom"),
            ("p_value", "--p-value"),
            ("min_tumor_freq", "--min-tumor-freq"),
            ("max_normal_freq", "--max-normal-freq"),
            ("somatic_p_value", "--somatic-p-value"),
        ]
        for key, flag in pairs:
            if kw.get(key) is not None:
                cmd += [flag, str(kw[key])]
        if kw.get("strand_filter") is not None:
            cmd += ["--strand-filter", str(kw["strand_filter"])]
        if kw.get("output_vcf") is not None:
            cmd += ["--output-vcf", str(kw["output_vcf"])]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        launcher = self._launcher()
        cmd: list[str] = list(launcher) + [subcommand]

        if subcommand in _STDOUT_SUBCMDS:
            inp = kw.get("input")
            if not inp:
                raise ValueError(f"{subcommand} 缺少必填参数 input（mpileup 文件）")
            cmd.append(str(inp))
            self._add_common(cmd, kw)

        elif subcommand in ("somatic", "copynumber"):
            inp = kw.get("input")
            if not inp:
                raise ValueError(f"{subcommand} 缺少必填参数 input（paired 或 normal mpileup）")
            cmd.append(str(inp))
            if kw.get("tumor"):
                cmd.append(str(kw["tumor"]))
            self._add_common(cmd, kw)
            out = kw.get("output_basename")
            if out:
                cmd.append(str(out))

        elif subcommand == "processSomatic":
            inp = kw.get("input")
            if not inp:
                raise ValueError("processSomatic 缺少必填参数 input（somatic 输出前缀）")
            cmd.append(str(inp))
            self._add_common(cmd, kw)

        elif subcommand == "fpfilter":
            vcf = kw.get("vcf_file")
            bam = kw.get("bam_file")
            out = kw.get("output_file")
            if not (vcf and bam and out):
                raise ValueError("fpfilter 需要同时给出 --vcf-file / --bam-file / --output-file")
            cmd += ["--vcf-file", str(vcf), "--bam-file", str(bam), "--output-file", str(out)]
            if kw.get("min_depth") is not None:
                cmd += ["--min-depth", str(kw["min_depth"])]
            if kw.get("min_var_count") is not None:
                cmd += ["--min-var-count", str(kw["min_var_count"])]
            if kw.get("min_var_freq") is not None:
                cmd += ["--min-var-freq", str(kw["min_var_freq"])]

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
    p.add_argument("--threads", type=int, help="接口统一用；VarScan 单线程，不传给 varscan")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--min-coverage", dest="min_coverage", type=int, help="最小覆盖深度（文档示例 8）")
    p.add_argument("--min-reads2", dest="min_reads2", type=int, help="支持变异的最小 reads 数（文档示例 2）")
    p.add_argument("--min-avg-qual", dest="min_avg_qual", type=int, help="最小平均碱基质量（文档示例 15）")
    p.add_argument("--min-var-freq", dest="min_var_freq", type=float, help="最小变异等位频率（文档示例 0.1）")
    p.add_argument("--min-freq-for-hom", dest="min_freq_for_hom", type=float, help="判定纯合的最小频率")
    p.add_argument("--p-value", dest="p_value", type=float, help="显著性 p 值阈值（文档示例 0.05）")
    p.add_argument("--min-tumor-freq", dest="min_tumor_freq", type=float, help="肿瘤最小变异频率")
    p.add_argument("--max-normal-freq", dest="max_normal_freq", type=float, help="正常样本最大变异频率")
    p.add_argument("--somatic-p-value", dest="somatic_p_value", type=float, help="体细胞变异 p 值阈值")
    p.add_argument("--strand-filter", dest="strand_filter", type=int, help="链偏倚过滤（1/0）")
    p.add_argument("--output-vcf", dest="output_vcf", type=int, help="输出 VCF（1 为是，0 为否）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="varscan-skill",
        description="varscan native 技能驱动（mpileup -> 变异检测；JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _stdout_parser(name: str) -> None:
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("input", help="mpileup 文件")
        _add_common_opts(ps)
        ps.add_argument("-o", "--output", help="输出 VCF 文件（stdout 落盘）")
        ps.add_argument("--extra-args", help="透传给 varscan 的额外参数")
        _add_runtime_opts(ps)

    for name in _STDOUT_SUBCMDS:
        _stdout_parser(name)

    for name in ("somatic", "copynumber"):
        pc = sub.add_parser(name, help=SUBCOMMANDS[name])
        pc.add_argument("input", help="paired mpileup（含双样本）或 normal mpileup")
        pc.add_argument("output_basename", nargs="?", help="输出前缀（生成 .snp.vcf/.indel.vcf 等）")
        pc.add_argument("--tumor", help="tumor mpileup（normal+tumor 双文件用法；paired 单文件时省略）")
        _add_common_opts(pc)
        pc.add_argument("--extra-args", help="透传给 varscan 的额外参数")
        _add_runtime_opts(pc)

    pp = sub.add_parser("processSomatic", help=SUBCOMMANDS["processSomatic"])
    pp.add_argument("input", help="somatic 输出前缀")
    _add_common_opts(pp)
    pp.add_argument("--extra-args", help="透传给 varscan 的额外参数")
    _add_runtime_opts(pp)

    pf = sub.add_parser("fpfilter", help=SUBCOMMANDS["fpfilter"])
    pf.add_argument("--vcf-file", dest="vcf_file", help="输入 VCF")
    pf.add_argument("--bam-file", dest="bam_file", help="输入（肿瘤）BAM")
    pf.add_argument("--output-file", dest="output_file", help="输出文件")
    pf.add_argument("--min-depth", dest="min_depth", type=int, help="最小深度")
    pf.add_argument("--min-var-count", dest="min_var_count", type=int, help="最小变异 reads 数")
    pf.add_argument("--min-var-freq", dest="min_var_freq", type=float, help="最小变异频率")
    pf.add_argument("--extra-args", help="透传给 varscan 的额外参数")
    _add_runtime_opts(pf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = VarscanSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = VarscanSkill()
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

    # mpileup2* 写 VCF 到 stdout，给出 --output 时落盘
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
