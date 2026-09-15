#!/usr/bin/env python3
"""pheatmap native 标准入口驱动（pheatmap R 包，经 Rscript 调用）。

pheatmap 以 R 函数库形态分发（CRAN，无独立命令行二进制），本驱动用
`Rscript -e "<R 表达式>"` 直接调用 pheatmap() 绘制差异基因表达热图
（支持按行/列标准化、双向聚类、列注释、log2 转换；无需额外 .R 脚本）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py plot DEG_expression_matrix.txt -o heatmap.pdf \
       --scale row --show-rownames false --annotation sample_annotation.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

线程（--threads）：pheatmap 为单线程绘图，`--threads` 仅作接口统一并在加载包前设置
OMP/OPENBLAS/MKL/VECLIB 线程数环境变量（对大规模距离计算/聚类有边际影响）；
优先级：--threads > per_subcommand_threads > default_cpus。

前置：R >= 4.1 且已安装 pheatmap（conda r-pheatmap / CRAN install.packages("pheatmap")）；
或使用模块 README 的官方 biocontainer 镜像（quay.io/biocontainers/r-pheatmap）。
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

SUBCOMMANDS = {
    "plot": "绘制表达矩阵热图（pheatmap；支持标准化/双向聚类/列注释/log2 转换）",
}


def _rstr(value: object) -> str:
    """把 Python 字符串转成 R 双引号字符串字面量（转义反斜杠与双引号）。"""
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def _rbool(value: object) -> str:
    """把 Python 布尔/字符串转成 R 的 TRUE/FALSE 字面量。"""
    if isinstance(value, str):
        return "TRUE" if value.strip().lower() in ("1", "true", "yes", "t") else "FALSE"
    return "TRUE" if value else "FALSE"


class PheatmapSkill(base.SkillBase):
    software = "pheatmap"
    binary = "Rscript"

    def _preamble(self, threads: int) -> list[str]:
        t = str(threads)
        return [
            "suppressPackageStartupMessages(library(pheatmap))",
            "Sys.setenv(OMP_NUM_THREADS=%s, OPENBLAS_NUM_THREADS=%s, MKL_NUM_THREADS=%s, "
            "VECLIB_MAXIMUM_THREADS=%s)" % (_rstr(t), _rstr(t), _rstr(t), _rstr(t)),
            f"options(mc.cores={threads})",
            f"Sys.setenv(TMPDIR={_rstr(self.tmpdir)})",
        ]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 `Rscript -e "<expr>"`；expr 拼装 pheatmap() 绘图 R 代码。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        matrix_in = kw.get("matrix")
        output = kw.get("output")
        if not matrix_in:
            raise RuntimeError("plot 需要表达矩阵：matrix <文件，行基因、列样品>")
        if not output:
            raise RuntimeError("plot 需要输出图片：-o/--output <*.pdf|*.png>")

        scale = str(kw.get("scale") or "row").lower()
        if scale not in ("none", "row", "column"):
            raise RuntimeError("--scale 仅支持 none|row|column")

        lines = self._preamble(threads)
        lines.append(
            "m <- as.matrix(read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", "
            "check.names=FALSE))" % _rstr(matrix_in)
        )
        if kw.get("log2", True):
            lines.append("m <- log2(m + 1)")
        if kw.get("annotation"):
            lines.append(
                "ann <- read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", check.names=FALSE)"
                % _rstr(kw["annotation"])
            )
        else:
            lines.append("ann <- NA")

        title = str(kw.get("title") or "Differential Gene Expression Heatmap")
        width = float(kw.get("width") if kw.get("width") is not None else 8)
        height = float(kw.get("height") if kw.get("height") is not None else 10)
        lines.append(
            "pheatmap(m, scale=%s, show_rownames=%s, show_colnames=%s, cluster_rows=%s, "
            "cluster_cols=%s, treeheight_row=20, treeheight_col=20, "
            "color=colorRampPalette(c(\"navy\", \"white\", \"firebrick3\"))(100), main=%s, "
            "annotation_col=ann, filename=%s, width=%s, height=%s)"
            % (
                _rstr(scale), _rbool(kw.get("show_rownames", False)),
                _rbool(kw.get("show_colnames", True)), _rbool(kw.get("cluster_rows", True)),
                _rbool(kw.get("cluster_cols", True)), _rstr(title), _rstr(output),
                repr(width), repr(height),
            )
        )
        lines.append(
            'cat("PHEATMAP_OK\\tplot\\trows=", nrow(m), "\\tcols=", ncol(m), "\\n", sep="")'
        )
        return [rscript, "-e", ";\n".join(lines)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, default=None,
                   help="线程数（pheatmap 单线程绘图的接口统一参数；默认取 meta 建议值）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="pheatmap-skill",
        description="pheatmap native 技能驱动（Rscript 调用 pheatmap() 绘制热图）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    pp.add_argument("matrix", help="表达矩阵（行基因、列样品，Tab 分隔，含首行样品名/首列基因名）")
    pp.add_argument("-o", "--output", required=True, help="输出图片（按扩展名 *.pdf / *.png）")
    pp.add_argument("--scale", default="row", choices=["none", "row", "column"],
                    help="标准化方式（默认 row，按行标准化）")
    pp.add_argument("--log2", dest="log2", action="store_true", default=True,
                    help="先做 log2(x+1) 转换（默认开）")
    pp.add_argument("--no-log2", dest="log2", action="store_false", help="关闭 log2 转换")
    pp.add_argument("--cluster-rows", dest="cluster_rows", action="store_true", default=True,
                    help="行聚类（默认开）")
    pp.add_argument("--no-cluster-rows", dest="cluster_rows", action="store_false", help="关闭行聚类")
    pp.add_argument("--cluster-cols", dest="cluster_cols", action="store_true", default=True,
                    help="列聚类（默认开）")
    pp.add_argument("--no-cluster-cols", dest="cluster_cols", action="store_false", help="关闭列聚类")
    pp.add_argument("--show-rownames", dest="show_rownames", action="store_true", default=False,
                    help="显示基因名（默认关，基因太多时不建议开）")
    pp.add_argument("--no-show-rownames", dest="show_rownames", action="store_false")
    pp.add_argument("--show-colnames", dest="show_colnames", action="store_true", default=True,
                    help="显示样品名（默认开）")
    pp.add_argument("--no-show-colnames", dest="show_colnames", action="store_false")
    pp.add_argument("--annotation", help="列注释表（行样品、列注释；可选）")
    pp.add_argument("--title", default="Differential Gene Expression Heatmap", help="图标题")
    pp.add_argument("--width", type=float, default=8, help="输出宽度（英寸，默认 8）")
    pp.add_argument("--height", type=float, default=10, help="输出高度（英寸，默认 10）")
    _add_runtime_opts(pp)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = PheatmapSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PheatmapSkill()
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
