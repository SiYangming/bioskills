#!/usr/bin/env python3
"""ggplot2 native 标准入口驱动（ggplot2 R 包，经 Rscript 调用）。

ggplot2 以 R 函数库形态分发（CRAN，无独立命令行二进制），本驱动用
`Rscript -e "<R 表达式>"` 直接调用 ggplot2 绘制差异表达火山图（x=log2FC，y=-log10(padj)，
按阈值分组着色 + 阈值虚线 + ggsave 输出；无需额外 .R 脚本）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py volcano DESeq2_results.txt -o volcano_plot.pdf \
       --lfc-cutoff 1 --padj-cutoff 0.05
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

线程（--threads）：ggplot2 为单线程绘图，`--threads` 仅作接口统一并在加载包前设置
OMP/OPENBLAS/MKL/VECLIB 线程数环境变量；优先级：--threads > per_subcommand_threads > default_cpus。

前置：R >= 4.1 且已安装 ggplot2（conda r-ggplot2 / CRAN install.packages("ggplot2")）；
或使用模块 README 的官方 biocontainer 镜像（quay.io/biocontainers/r-ggplot2）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "volcano": "差异表达火山图（ggplot2；log2FC vs -log10(padj)，阈值分组着色 + ggsave 输出）",
}

_VALID_COL = re.compile(r"^[A-Za-z._][A-Za-z0-9._]*$")


def _rstr(value: object) -> str:
    """把 Python 字符串转成 R 双引号字符串字面量（转义反斜杠与双引号）。"""
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


class Ggplot2Skill(base.SkillBase):
    software = "ggplot2"
    binary = "Rscript"

    def _preamble(self, threads: int) -> list[str]:
        t = str(threads)
        return [
            "suppressPackageStartupMessages(library(ggplot2))",
            "Sys.setenv(OMP_NUM_THREADS=%s, OPENBLAS_NUM_THREADS=%s, MKL_NUM_THREADS=%s, "
            "VECLIB_MAXIMUM_THREADS=%s)" % (_rstr(t), _rstr(t), _rstr(t), _rstr(t)),
            f"options(mc.cores={threads})",
            f"Sys.setenv(TMPDIR={_rstr(self.tmpdir)})",
        ]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 `Rscript -e "<expr>"`；expr 拼装 ggplot2 火山图 R 代码。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        deg_table = kw.get("deg_table")
        output = kw.get("output")
        if not deg_table:
            raise RuntimeError("volcano 需要差异分析结果表：deg_table <含 log2FC/padj 列>")
        if not output:
            raise RuntimeError("volcano 需要输出图片：-o/--output <*.pdf|*.png>")

        lfc_col = str(kw.get("lfc_col") or "log2FoldChange")
        padj_col = str(kw.get("padj_col") or "padj")
        for col in (lfc_col, padj_col):
            if not _VALID_COL.match(col):
                raise RuntimeError(f"非法列名: {col!r}（仅允许字母/数字/._ 且不以数字开头）")

        padj_cut = float(kw.get("padj_cutoff") if kw.get("padj_cutoff") is not None else 0.05)
        lfc_cut = float(kw.get("lfc_cutoff") if kw.get("lfc_cutoff") is not None else 1.0)
        title = str(kw.get("title") or "Volcano Plot of Differential Gene Expression")
        width = float(kw.get("width") if kw.get("width") is not None else 8)
        height = float(kw.get("height") if kw.get("height") is not None else 6)

        lines = self._preamble(threads)
        lines.append(
            "res0 <- read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", check.names=FALSE)"
            % _rstr(deg_table)
        )
        lines.append(f"df <- data.frame(lfc=res0[[{_rstr(lfc_col)}]], padj=res0[[{_rstr(padj_col)}]])")
        lines.append('df$group <- "Not significant"')
        lines.append(
            "df$group[df$padj < %s & df$lfc > %s] <- \"Up-regulated\""
            % (repr(padj_cut), repr(lfc_cut))
        )
        lines.append(
            "df$group[df$padj < %s & df$lfc < -%s] <- \"Down-regulated\""
            % (repr(padj_cut), repr(lfc_cut))
        )
        lines.append("df$group <- factor(df$group, levels=c(\"Down-regulated\", \"Not significant\", \"Up-regulated\"))")
        lines.append(
            "p <- ggplot(df, aes(x=lfc, y=-log10(padj), color=group)) + "
            "geom_point(alpha=0.5, size=1) + "
            "scale_color_manual(values=c(\"Down-regulated\"=\"blue\", \"Not significant\"=\"gray\", "
            "\"Up-regulated\"=\"red\")) + "
            "geom_vline(xintercept=c(-%s, %s), linetype=\"dashed\", color=\"black\") + "
            "geom_hline(yintercept=-log10(%s), linetype=\"dashed\", color=\"black\") + "
            "theme_bw() + labs(x=\"log2(Fold Change)\", y=\"-log10(Adjusted p-value)\", title=%s) + "
            "theme(plot.title=element_text(hjust=0.5))"
            % (repr(lfc_cut), repr(lfc_cut), repr(padj_cut), _rstr(title))
        )
        lines.append(f"ggsave({_rstr(output)}, p, width={repr(width)}, height={repr(height)})")
        lines.append(
            'cat("GGPLOT2_OK\\tvolcano\\tup=", sum(df$group == "Up-regulated"), "\\tdown=", '
            'sum(df$group == "Down-regulated"), "\\n", sep="")'
        )
        return [rscript, "-e", ";\n".join(lines)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, default=None,
                   help="线程数（ggplot2 单线程绘图的接口统一参数；默认取 meta 建议值）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ggplot2-skill",
        description="ggplot2 native 技能驱动（Rscript 调用 ggplot2 绘制火山图）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pv = sub.add_parser("volcano", help=SUBCOMMANDS["volcano"])
    pv.add_argument("deg_table", help="差异分析结果表（含 log2FoldChange 与 padj 列，Tab 分隔）")
    pv.add_argument("-o", "--output", required=True, help="输出图片（按扩展名 *.pdf / *.png）")
    pv.add_argument("--lfc-col", default="log2FoldChange", help="log2FC 列名（默认 log2FoldChange）")
    pv.add_argument("--padj-col", default="padj", help="校正 p 值列名（默认 padj）")
    pv.add_argument("--lfc-cutoff", type=float, default=1.0, help="|log2FC| 阈值（默认 1）")
    pv.add_argument("--padj-cutoff", type=float, default=0.05, help="padj 阈值（默认 0.05）")
    pv.add_argument("--title", default="Volcano Plot of Differential Gene Expression", help="图标题")
    pv.add_argument("--width", type=float, default=8, help="输出宽度（英寸，默认 8）")
    pv.add_argument("--height", type=float, default=6, help="输出高度（英寸，默认 6）")
    _add_runtime_opts(pv)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = Ggplot2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Ggplot2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "schema", "list_commands")
          and v is not None}
    kw["threads"] = ns.threads

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
