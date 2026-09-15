#!/usr/bin/env python3
"""qiime2 native 标准入口驱动（QIIME 2 2026.1 amplicon 发行版）。

QIIME 2 的 CLI 是「插件-动作」两段式：`qiime <plugin> <action> [options]`，
例如 `qiime tools import ...` / `qiime dada2 denoise-single ...`。本驱动把子命令
写成点分两段式键（如 `tools.import`、`feature-table.summarize`），由 build_command
还原为 `qiime <plugin> <action> ...` 的 argv。

两种调用模式：
1. CLI 直跑（人类 / Shell）：动作参数原样透传（本驱动不解析每个 qiime 选项）
   python main.py tools.import --type EMPSingleEndSequences \
       --input-path 01.emp-single-end-sequences \
       --output-path 03.qimme2_prepare_data/emp-single-end-sequences.qza
   python main.py dada2.denoise-single \
       --i-demultiplexed-seqs demux.qza --p-trim-left 0 --p-trunc-len 120 \
       --o-representative-sequences rep-seqs.qza --o-table table.qza --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的「插件-动作」

线程：对支持并行的动作自动注入线程参数（dada2 / alignment / phylogeny 用 --p-n-threads，
feature-classifier / diversity 用 --p-n-jobs）；否则线程仅作调度参考。
临时目录：QIIME 2 无全局 --tmpdir 选项，--tmpdir 覆盖进程 TMPDIR 环境变量。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 插件-动作 语义清单（点分两段式；用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "tools.import": "导入数据为 QZA artifact（--type/--input-path/--output-path/--source-format）",
    "tools.export": "导出 QZA/QZV 为普通文件（--input-path/--output-path 或 --output-dir）",
    "tools.peek": "查看 QZA 数据类型/格式（位置参数：artifact）",
    "tools.view": "在浏览器可视化查看 QZV",
    "demux.emp-single": "EMP 单端数据按 barcode 拆样（--i-seqs/--m-barcodes-file/--m-barcodes-category/--o-per-sample-sequences）",
    "demux.summarize": "拆分结果统计可视化（--i-data/--o-visualization）",
    "dada2.denoise-single": "DADA2 单端去噪建特征表（--i-demultiplexed-seqs/--p-trim-left/--p-trunc-len/--p-n-threads）",
    "dada2.denoise-paired": "DADA2 双端去噪建特征表（--p-trim-left-f/-r/--p-trunc-len-f/-r/--p-n-threads）",
    "deblur.denoise-16S": "Deblur 16S 去噪（单端；--i-demultiplexed-seqs/--p-trim-length）",
    "feature-table.summarize": "特征表统计可视化（--i-table/--o-visualization/--m-sample-metadata-file）",
    "feature-table.tabulate-seqs": "代表序列汇总可视化（--i-data/--o-visualization）",
    "feature-table.filter-samples": "按元数据筛选样品（--i-table/--p-where/--o-filtered-table）",
    "alignment.mafft": "MAFFT 多序列比对（--i-sequences/--p-n-threads/--o-alignment）",
    "alignment.mask": "去除高变/非保守位点（--i-alignment/--o-masked-alignment）",
    "phylogeny.fasttree": "FastTree 建无根树（--i-alignment/--p-n-threads/--o-tree）",
    "phylogeny.midpoint-root": "midpoint 法将无根树转有根树（--i-tree/--o-rooted-tree）",
    "diversity.core-metrics-phylogenetic": "核心多样性指标矩阵（--i-phylogeny/--i-table/--p-sampling-depth/--output-dir）",
    "diversity.alpha-group-significance": "Alpha 多样性组间显著性（--i-alpha-diversity/--m-metadata-file/--o-visualization）",
    "diversity.beta-group-significance": "Beta 多样性组间显著性（--i-distance-matrix/--m-metadata-category/--p-pairwise）",
    "emperor.plot": "PCoA 主坐标分析可视化（--i-pcoa/--m-metadata-file/--o-visualization）",
    "feature-classifier.extract-reads": "按引物提取参考序列reads（--i-sequences/--p-f-primer/--p-r-primer/--p-trunc-len/--p-n-jobs）",
    "feature-classifier.fit-classifier-naive-bayes": "训练朴素贝叶斯分类器（--i-reference-reads/--i-reference-taxonomy/--o-classifier/--p-n-jobs）",
    "feature-classifier.classify-sklearn": "sklearn 分类器物种注释（--i-classifier/--i-reads/--o-classification/--p-n-jobs）",
    "taxa.barplot": "物种组成堆叠柱状图（--i-table/--i-taxonomy/--m-metadata-file/--o-visualization）",
    "taxa.collapse": "按分类水平折叠特征表（--i-table/--i-taxonomy/--p-level/--o-collapsed-table）",
    "composition.add-pseudocount": "为零值加 pseudocount（--i-table/--o-composition-table）",
    "composition.ancom": "ANCOM 差异丰度分析（--i-table/--m-metadata-category/--o-visualization）",
    "metadata.tabulate": "元数据/分类结果表格可视化（--m-input-file/--o-visualization）",
    "info": "打印 QIIME 2 安装信息与版本（qiime info）",
}

# 支持并行的动作 -> 线程参数名（其余动作不注入线程）
THREAD_FLAG = {
    "dada2.denoise-single": "--p-n-threads",
    "dada2.denoise-paired": "--p-n-threads",
    "alignment.mafft": "--p-n-threads",
    "phylogeny.fasttree": "--p-n-threads",
    "feature-classifier.extract-reads": "--p-n-jobs",
    "feature-classifier.fit-classifier-naive-bayes": "--p-n-jobs",
    "feature-classifier.classify-sklearn": "--p-n-jobs",
    "diversity.core-metrics-phylogenetic": "--p-n-jobs",
}


class Qiime2Skill(base.SkillBase):
    software = "qiime2"
    binary = "qiime"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """按「插件-动作」两段式构造 qiime 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（--list-commands 查看支持的插件-动作）")

        binary = self._resolve_binary()

        # 两段式：plugin.action -> ["qiime", "plugin", "action"]；"info" 为顶层命令
        if "." in subcommand:
            plugin, action = subcommand.split(".", 1)
            cmd: list[str] = [binary, plugin, action]
        else:
            cmd = [binary, subcommand]

        # 动作参数原样透传（本驱动不解析每个 qiime 选项）
        extra = kw.get("args") or []
        if isinstance(extra, str):
            extra = extra.split()
        cmd += [str(a) for a in extra]

        # 线程注入：仅对支持并行的动作；用户已自带线程参数则不覆盖
        flag = THREAD_FLAG.get(subcommand)
        if flag and flag not in cmd:
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += [flag, str(threads)]

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="qiime2-skill",
        description="qiime2 native 技能驱动（QIIME 2 2026.1；插件-动作两段式；自动线程/TMPDIR 优化）",
        allow_abbrev=False,
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的插件-动作")
    sub = p.add_subparsers(dest="subcommand", metavar="<plugin.action>")
    for name, desc in SUBCOMMANDS.items():
        sp = sub.add_parser(name, help=desc, description=desc, allow_abbrev=False)
        sp.add_argument("args", nargs="*",
                        help="qiime 动作参数（原样透传，如 --i-demultiplexed-seqs demux.qza）")
        _add_runtime_opts(sp)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _split_runtime_opts(tokens: list[str]) -> tuple[list[str], int | None, str | None]:
    """从子命令后的 token 中抽出 --threads/--tmpdir，其余动作参数**保持原始顺序**。

    QIIME 2 动作参数（--i-*/--p-*/--o-*/--m-*）需原样透传且顺序不得打乱，
    argparse 的「位置参数 + 未知选项」会丢失选项/取值相邻关系，故此处手工拆分。
    """
    rest: list[str] = []
    threads: int | None = None
    tmpdir: str | None = None
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "--threads" and i + 1 < len(tokens):
            threads = int(tokens[i + 1]); i += 2; continue
        if t.startswith("--threads="):
            threads = int(t.split("=", 1)[1]); i += 1; continue
        if t == "--tmpdir" and i + 1 < len(tokens):
            tmpdir = tokens[i + 1]; i += 2; continue
        if t.startswith("--tmpdir="):
            tmpdir = t.split("=", 1)[1]; i += 1; continue
        rest.append(t)
        i += 1
    return rest, threads, tmpdir


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        width = max(len(k) for k in SUBCOMMANDS)
        for k, v in SUBCOMMANDS.items():
            print(f"{k:{width}s}  {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(Qiime2Skill().schema(), indent=2, ensure_ascii=False))
        return 0

    if not args or args[0] in ("-h", "--help"):
        build_parser().print_help(sys.stdout if args else sys.stderr)
        return 0 if args else 2

    subcommand, rest = args[0], args[1:]
    if subcommand not in SUBCOMMANDS:
        print(f"[ERROR] 未知子命令: {subcommand}（--list-commands 查看支持的插件-动作）",
              file=sys.stderr)
        return 2

    action_args, threads, tmpdir = _split_runtime_opts(rest)

    skill = Qiime2Skill()
    if tmpdir:
        skill.tmpdir = tmpdir
        skill.env_vars["TMPDIR"] = tmpdir

    try:
        result = skill.run(subcommand, args=action_args, threads=threads)
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
