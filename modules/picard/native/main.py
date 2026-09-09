#!/usr/bin/env python3
"""picard native 标准入口驱动（Java CLI 驱动）。

Picard 是 Java 程序，官方发布物为单个 picard.jar，CLI 形如：
    picard MarkDuplicates I=in.bam O=out.bam M=metrics.txt [REMOVE_DUPLICATES=true]
    picard SortSam I=in.bam O=out.bam SORT_ORDER=queryname
    picard AddOrReplaceReadGroups I=in.bam O=out.bam RGID=x RGSM=x RGLB=l RGPL=ILLUMINA
conda / brew（picard-tools）/ biocontainer 提供 `picard` launcher（内部仍调 java -jar）。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：子命令用**小写**工具名，自动映射真实 Picard 工具名：
   python main.py markduplicates -I sample.sorted.bam -O sample.dedup.bam -M metrics.txt
   python main.py sortsam -I sample.bam -O sample.qname.bam --sort-order queryname
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位入口：优先 PATH 上 `picard`（bioconda/brew/容器 wrapper）；否则 PICARD_JAR
  环境变量 → conda share / ~/software 常见位置 picard-*.jar，以 `java -jar` 调用。
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

# 子命令（小写） -> 真实 Picard 工具名
SUBCOMMANDS = {
    "markduplicates": "MarkDuplicates：标记/去除 PCR 重复（-M metrics 必需）",
    "sortsam": "SortSam：coordinate / queryname 排序",
    "addorreplacereadgroups": "AddOrReplaceReadGroups：写入/替换 RG 标签",
    "collectinsertsizemetrics": "CollectInsertSizeMetrics：插入片段分布统计（-M metrics）",
    "validatesamfile": "ValidateSamFile：BAM/SAM 完整性校验（SUMMARY 模式）",
    "createsequencedictionary": "CreateSequenceDictionary：参考 FASTA -> .dict",
    "mergesamfiles": "MergeSamFiles：合并多个 BAM（-I 可重复）",
    "samtofastq": "SamToFastq：BAM -> FASTQ（要求 queryname 排序输入）",
}

_JAR_GLOBS = [
    "PICARD_JAR",  # 环境变量（绝对路径）
    "{conda}/share/picard*/picard*.jar",
    "~/software/picard*/picard*.jar",
]

# Java 入口约束：jar 兜底时须宿主有 java
def _expand_jar_candidates() -> list[str]:
    cands: list[str] = []
    env_jar = os.environ.get("PICARD_JAR")
    if env_jar:
        cands.append(env_jar)
    conda = os.environ.get("CONDA_PREFIX", "")
    for pat in _JAR_GLOBS[1:]:
        p = pat.format(conda=conda)
        if p.startswith("~"):
            p = str(Path(p).expanduser())
        cands.append(p)
    return cands


class PicardSkill(base.SkillBase):
    software = "picard"
    binary = "picard"

    def _locate_jar(self) -> str | None:
        for c in _expand_jar_candidates():
            hits = sorted(glob.glob(c))
            if hits:
                return hits[0]
        return None

    def _resolve_launcher(self, dry_run: bool = False) -> list[str] | None:
        """返回命令前缀：['picard'] 或 ['java','-jar',jar]；dry_run 给占位名。"""
        if dry_run:
            return [self.binary]
        wrapper = base.which("picard")
        if wrapper:
            return [wrapper]
        jar = self._locate_jar()
        if jar:
            java = base.which("java")
            if not java:
                raise RuntimeError(
                    "已定位 picard jar 但 PATH 中无 java；请先安装 Java 17+ "
                    "（conda: mamba install -n <env> -c conda-forge openjdk）"
                )
            return [java, "-jar", jar]
        return None

    def _kv(self, cmd: list[str], flag: str, key: str, kw: dict, default: str | None = None) -> None:
        """追加 Picard 'KEY=value' 风格参数（value 为假值时用 default）。"""
        val = kw.get(key)
        if val is None or val is False or val == "":
            if default is None:
                return
            val = default
        cmd.append(f"{flag}={val}")

    def _tool(self, subcommand: str) -> str:
        return SUBCOMMANDS[subcommand].split("：")[0]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        launcher = self._resolve_launcher(bool(kw.get("dry_run")))
        if launcher is None:
            raise RuntimeError(
                "未找到 picard launcher 或 picard-*.jar；请先安装：conda/mamba"
                "（bioconda::picard）、brew（picard-tools）或官方 picard.jar"
                "（export PICARD_JAR=/path/to/picard.jar）"
            )
        cmd: list[str] = list(launcher)
        cmd.append(self._tool(subcommand))
        extra_tokens = str(kw.get("extra_args") or "").split()

        # 输入解析：mergesamfiles 支持 -I 多次（kw['inputs'] list），其余单 -I
        inputs = kw.get("inputs")
        if inputs:
            items = inputs if isinstance(inputs, list) else [inputs]
            for it in items:
                cmd.append(f"I={it}")
        else:
            inp = kw.get("input")
            if inp:
                cmd.append(f"I={inp}")

        if subcommand == "markduplicates":
            self._kv(cmd, "O", "output", kw, default="dedup.bam")
            self._kv(cmd, "M", "metrics", kw)
            if kw.get("remove_duplicates"):
                cmd.append("REMOVE_DUPLICATES=true")
        elif subcommand == "sortsam":
            self._kv(cmd, "O", "output", kw, default="sorted.bam")
            self._kv(cmd, "SORT_ORDER", "sort_order", kw, default="coordinate")
        elif subcommand == "addorreplacereadgroups":
            self._kv(cmd, "O", "output", kw, default="rg.bam")
            self._kv(cmd, "RGID", "read_group_id", kw)
            self._kv(cmd, "RGSM", "sample_name", kw)
            self._kv(cmd, "RGLB", "library", kw)
            self._kv(cmd, "RGPL", "platform", kw, default="ILLUMINA")
            self._kv(cmd, "RGPU", "platform_unit", kw)
            self._kv(cmd, "RGCN", "center", kw)
        elif subcommand == "collectinsertsizemetrics":
            self._kv(cmd, "O", "output", kw, default="insert_metrics.txt")
            self._kv(cmd, "H", "histogram", kw)
        elif subcommand == "validatesamfile":
            self._kv(cmd, "O", "output", kw)
            cmd.append("MODE=SUMMARY")
        elif subcommand == "createsequencedictionary":
            ref = kw.get("reference")
            if not ref:
                raise ValueError("createsequencedictionary 缺少必填参数 reference（R= FASTA）")
            cmd.append(f"R={ref}")
            self._kv(cmd, "O", "output", kw)
        elif subcommand == "mergesamfiles":
            if not inputs:
                raise ValueError("mergesamfiles 至少需要 1 个 -I 输入")
            self._kv(cmd, "O", "output", kw, default="merged.bam")
            self._kv(cmd, "SORT_ORDER", "sort_order", kw, default="coordinate")
        elif subcommand == "samtofastq":
            self._kv(cmd, "F", "fastq1", kw)
            self._kv(cmd, "F2", "fastq2", kw)
            self._kv(cmd, "UNPAIRED", "unpaired_fastq", kw)

        cmd += extra_tokens
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项。"""
    p.add_argument("--threads", type=int, help="CPU 提示（Picard 主要资源是 JVM 内存）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")
    p.add_argument("--extra-args", dest="extra_args", help="透传额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="picard-skill",
        description="picard native 技能驱动（I=/O= 风格；JVM 堆内存经 JAVA_TOOL_OPTIONS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    for name in ("markduplicates", "sortsam", "addorreplacereadgroups",
                 "collectinsertsizemetrics", "validatesamfile", "samtofastq"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("-I", "--input", help="输入 SAM/BAM/CRAM")
        _add_output_common(ps, name)
        _add_runtime_opts(ps)

    pcs = sub.add_parser("createsequencedictionary", help=SUBCOMMANDS["createsequencedictionary"])
    pcs.add_argument("-R", "--reference", help="参考 FASTA")
    pcs.add_argument("-O", "--output", help="输出 .dict（默认与 FASTA 同前缀）")
    _add_runtime_opts(pcs)

    pm = sub.add_parser("mergesamfiles", help=SUBCOMMANDS["mergesamfiles"])
    pm.add_argument("-I", "--input", dest="inputs", action="append", help="输入 BAM（可重复）")
    pm.add_argument("-O", "--output", help="合并输出 BAM")
    pm.add_argument("--sort-order", dest="sort_order", choices=["coordinate", "queryname"],
                    default="coordinate")
    _add_runtime_opts(pm)
    return p


def _add_output_common(p: argparse.ArgumentParser, name: str) -> None:
    """按工具添加 O/M 等选项。"""
    p.add_argument("-O", "--output", help="输出文件")
    if name in ("markduplicates", "collectinsertsizemetrics"):
        p.add_argument("-M", "--metrics", help="metrics 文本输出")
    if name == "markduplicates":
        p.add_argument("--remove-duplicates", action="store_true",
                       help="直接删除重复（默认仅标记）")
    if name == "sortsam":
        p.add_argument("--sort-order", dest="sort_order", choices=["coordinate", "queryname"],
                       default="coordinate")
    if name == "addorreplacereadgroups":
        p.add_argument("--read-group-id", dest="read_group_id")
        p.add_argument("--sample-name", dest="sample_name")
        p.add_argument("--library")
        p.add_argument("--platform", default="ILLUMINA")
        p.add_argument("--platform-unit", dest="platform_unit")
        p.add_argument("--center")
    if name == "collectinsertsizemetrics":
        p.add_argument("-H", "--histogram", help="直方图 PDF 输出")
    if name == "samtofastq":
        p.add_argument("-F", "--fastq1", help="R1 FASTQ 输出")
        p.add_argument("-F2", "--fastq2", help="R2 FASTQ 输出")
        p.add_argument("--unpaired", dest="unpaired_fastq", help="未配对 reads 输出")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:26s}  {v}")
        return 0
    if "--schema" in args:
        skill = PicardSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PicardSkill()
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
