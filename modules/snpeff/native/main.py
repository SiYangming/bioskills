#!/usr/bin/env python3
"""snpeff native 标准入口驱动（Java CLI 驱动）。

SnpEff 是 Java 程序，官方调用形如：
    java -Xmx2G -jar snpEff.jar eff -csvStats variants.csv -s variants.html \\
        -c snpEff.config -v -ud 500 <genome> variants.vcf > variant.SnpEff.vcf
    java -jar snpEff.jar build -c snpEff.config -gtf22 -v <genome>
conda（bioconda::snpeff）提供 `snpEff` wrapper（内部仍调 java）；官方
snpEff_latest_core.zip 解压后为 snpEff.jar，需宿主自备 JRE。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py eff -c snpEff.config -csv-stats v.csv -s v.html -ud 500 -o out.vcf \\
       malassezia_sympodialis variants.vcf
   python main.py build -c snpEff.config --gtf22 malassezia_sympodialis
   python main.py download GRCh38.105
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 入口定位：优先 PATH 上 `snpEff`（bioconda/biocontainer wrapper）；缺失时用
  SNPEFF_JAR 环境变量 → conda share / ~/software 常见位置的 snpEff.jar，
  以 `java <JAVA_OPTS> -jar` 调用（需宿主 java）。
- JVM 堆内存与临时目录经 JAVA_OPTS / TMPDIR 注入（env_vars）。
- eff 的注释结果写 stdout，由 main() 在给出 --output 时落盘（对齐文档重定向用法）。
- SnpEff 单线程；--threads 仅作接口统一，不传给 snpEff。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "eff": "变异功能注释（eff 为 SnpEff 默认命令；按 gene/transcript 注释功能影响）",
    "build": "用参考 FASTA + GTF/GFF3 构建自定义 SnpEff 数据库",
    "download": "下载官方预构建数据库（如 GRCh38.105）",
    "databases": "列出当前配置可用的数据库",
}

# snpEff.jar 常见候选位置（conda share / 用户前缀）
_JAR_GLOBS = [
    "{conda}/share/snpeff*/snpEff.jar",
    "{conda}/share/snpeff*/snpEff-*.jar",
    "{conda}/share/snpeff*/snpEff*/snpEff.jar",
    "~/software/snpEff*/snpEff.jar",
    "~/software/snpeff*/snpEff.jar",
]


class SnpeffSkill(base.SkillBase):
    software = "snpeff"
    binary = "snpEff"

    # -- 入口定位 --------------------------------------------------------- #
    def _locate_jar(self) -> str | None:
        env_jar = os.environ.get("SNPEFF_JAR")
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
        """返回命令前缀：['snpEff'] 或 ['java', *JAVA_OPTS, '-jar', jar]。"""
        try:
            return [self._resolve_binary()]
        except RuntimeError:
            jar = self._locate_jar()
            if not jar:
                raise RuntimeError(
                    "未找到 snpEff：PATH 上无 snpEff wrapper，且未定位到 snpEff.jar；"
                    "请 conda/mamba 安装（bioconda::snpeff=5.4.0c），或解压官方 "
                    "snpEff_latest_core.zip 并导出 SNPEFF_JAR=/path/to/snpEff.jar（需宿主 java）"
                )
            java = base.which("java")
            if not java:
                raise RuntimeError(
                    "已定位 snpEff.jar 但 PATH 中无 java；请先安装 JRE（conda: "
                    "mamba install -n <env> -c conda-forge openjdk）"
                )
            return [java, *self._java_opts(), "-jar", jar]

    # -- 命令构建 --------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        launcher = self._launcher()
        cmd: list[str] = list(launcher) + [subcommand]

        if subcommand == "eff":
            cfg = kw.get("config")
            if cfg:
                cmd += ["-c", str(cfg)]
            if kw.get("csv_stats"):
                cmd += ["-csvStats", str(kw["csv_stats"])]
            if kw.get("html_stats"):
                cmd += ["-s", str(kw["html_stats"])]
            if kw.get("input_format"):
                cmd += ["-i", str(kw["input_format"])]
            if kw.get("output_format"):
                cmd += ["-o", str(kw["output_format"])]
            if kw.get("interval"):
                cmd += ["-interval", str(kw["interval"])]
            if kw.get("updown") is not None:
                cmd += ["-ud", str(kw["updown"])]
            if kw.get("no_stats"):
                cmd.append("-noStats")
            if kw.get("verbose", True):
                cmd.append("-v")
            genome = kw.get("genome")
            if not genome:
                raise ValueError("eff 缺少必填参数 genome（SnpEff 数据库名）")
            cmd.append(str(genome))
            inp = kw.get("input")
            if inp:
                cmd.append(str(inp))

        elif subcommand == "build":
            if kw.get("config"):
                cmd += ["-c", str(kw["config"])]
            if kw.get("gtf22"):
                cmd.append("-gtf22")
            if kw.get("gff3"):
                cmd.append("-gff3")
            if kw.get("no_check_cds"):
                cmd.append("-noCheckCds")
            if kw.get("no_check_protein"):
                cmd.append("-noCheckProtein")
            if kw.get("verbose", True):
                cmd.append("-v")
            genome = kw.get("genome")
            if not genome:
                raise ValueError("build 缺少必填参数 genome（待构建数据库名）")
            cmd.append(str(genome))

        elif subcommand == "download":
            if kw.get("config"):
                cmd += ["-c", str(kw["config"])]
            if kw.get("verbose", True):
                cmd.append("-v")
            genome = kw.get("genome")
            if not genome:
                raise ValueError("download 缺少必填参数 genome（数据库名，如 GRCh38.105）")
            cmd.append(str(genome))

        elif subcommand == "databases":
            if kw.get("config"):
                cmd += ["-c", str(kw["config"])]
            if kw.get("verbose", True):
                cmd.append("-v")

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
    p.add_argument("--threads", type=int, help="接口统一用；SnpEff 单线程，不传给 snpEff")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="snpeff-skill",
        description="snpeff native 技能驱动（JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # eff
    pe = sub.add_parser("eff", help=SUBCOMMANDS["eff"])
    pe.add_argument("genome", help="SnpEff 数据库名（如 malassezia_sympodialis / GRCh38.105）")
    pe.add_argument("input", nargs="?", help="输入 VCF（SnpEff 从文件/stdin 读，结果写 stdout）")
    pe.add_argument("-c", "--config", help="snpEff.config 路径")
    pe.add_argument("--csv-stats", dest="csv_stats", help="输出 CSV 统计")
    pe.add_argument("-s", "--html-stats", dest="html_stats", help="输出 HTML 汇总报告")
    pe.add_argument("-ud", "--updown", type=int, help="上下游扩展距离（文档示例 500）")
    pe.add_argument("-i", "--input-format", dest="input_format", help="输入格式 vcf|gatk|bed")
    pe.add_argument("--format", dest="output_format", help="输出格式 vcf|gatk|bed（映射 -o）")
    pe.add_argument("--interval", help="仅注释指定区间（BED）")
    pe.add_argument("--no-stats", dest="no_stats", action="store_true", help="跳过统计（加速）")
    pe.add_argument("--no-verbose", dest="verbose", action="store_false", help="关闭 -v")
    pe.add_argument("-o", "--output", help="注释结果输出文件（stdout 落盘）")
    pe.add_argument("--extra-args", help="透传给 snpEff 的额外参数")
    _add_runtime_opts(pe)

    # build
    pb = sub.add_parser("build", help=SUBCOMMANDS["build"])
    pb.add_argument("genome", help="待构建数据库名")
    pb.add_argument("-c", "--config", help="snpEff.config 路径")
    pb.add_argument("--gtf22", action="store_true", help="使用 GTF（-gtf22）注释")
    pb.add_argument("--gff3", action="store_true", help="使用 GFF3 注释")
    pb.add_argument("--no-check-cds", dest="no_check_cds", action="store_true", help="跳过 CDS 检查")
    pb.add_argument("--no-check-protein", dest="no_check_protein", action="store_true", help="跳过蛋白检查")
    pb.add_argument("--no-verbose", dest="verbose", action="store_false", help="关闭 -v")
    pb.add_argument("--extra-args", help="透传给 snpEff 的额外参数")
    _add_runtime_opts(pb)

    # download
    pd = sub.add_parser("download", help=SUBCOMMANDS["download"])
    pd.add_argument("genome", help="要下载的数据库名（如 GRCh38.105）")
    pd.add_argument("-c", "--config", help="snpEff.config 路径")
    pd.add_argument("--no-verbose", dest="verbose", action="store_false", help="关闭 -v")
    pd.add_argument("--extra-args", help="透传给 snpEff 的额外参数")
    _add_runtime_opts(pd)

    # databases
    pdb = sub.add_parser("databases", help=SUBCOMMANDS["databases"])
    pdb.add_argument("-c", "--config", help="snpEff.config 路径")
    pdb.add_argument("--no-verbose", dest="verbose", action="store_false", help="关闭 -v")
    pdb.add_argument("--extra-args", help="透传给 snpEff 的额外参数")
    _add_runtime_opts(pdb)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = SnpeffSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SnpeffSkill()
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

    # eff 的注释结果写 stdout，给出 --output 时落盘
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
