#!/usr/bin/env python3
"""wgcna native 标准入口驱动（WGCNA R 包，经 Rscript 调用）。

WGCNA 以 R 函数库形态分发（CRAN，无独立命令行二进制），本驱动用
`Rscript -e "<R 表达式>"` 直接调用 goodSamplesGenes()/pickSoftThreshold()/
adjacency()/TOMsimilarity()/cutreeDynamic()/mergeCloseModules() 完成加权基因共表达
网络分析（无需额外 .R 脚本）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run   expression_matrix.txt --outdir wgcna_out --trait trait_data.txt
   python main.py check expression_matrix.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

线程（--threads）：映射 allowWGCNAThreads(nThreads=N)（WGCNA 多线程选项；NA/1 为单线程）；
优先级：--threads > per_subcommand_threads > default_cpus。

前置：R >= 4.1 且已安装 WGCNA（conda r-wgcna / CRAN install.packages("WGCNA")）；
或使用模块 README 的官方 biocontainer 镜像（quay.io/biocontainers/r-wgcna）。
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
    "run": "WGCNA 全流程（预处理→软阈值→邻接/TOM→模块识别→合并→模块-性状关联→导出）",
    "check": "数据质量检查（goodSamplesGenes：基因/样品缺失与低表达过滤建议）",
}


def _rstr(value: object) -> str:
    """把 Python 字符串转成 R 双引号字符串字面量（转义反斜杠与双引号）。"""
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


class WGCNAPythonSkill(base.SkillBase):
    software = "wgcna"
    binary = "Rscript"

    def _preamble(self, threads: int) -> list[str]:
        return [
            "suppressPackageStartupMessages(library(WGCNA))",
            "options(stringsAsFactors=FALSE)",
            f"try(allowWGCNAThreads(nThreads={threads}), silent=TRUE)",
            f"Sys.setenv(TMPDIR={_rstr(self.tmpdir)})",
        ]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 `Rscript -e "<expr>"`；expr 依子命令拼装 WGCNA R 代码。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        expr_in = kw.get("expr") if "expr" in kw else kw.get("expression")
        if not expr_in:
            raise RuntimeError(f"{subcommand} 需要表达矩阵：expr <文件，行基因、列样品>")

        lines = self._preamble(threads)
        lines.append(
            "datExpr <- t(read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", "
            "check.names=FALSE))" % _rstr(expr_in)
        )
        lines.append("gsg <- goodSamplesGenes(datExpr, verbose=0)")
        lines.append("datExpr <- datExpr[, gsg$goodGenes]")

        if subcommand == "check":
            lines.append(
                'cat("WGCNA_OK\\tcheck\\tgoodGenes=", sum(gsg$goodGenes), "\\tgoodSamples=", '
                'sum(gsg$goodSamples), "\\ttotalGenes=", ncol(datExpr), "\\ttotalSamples=", '
                'nrow(datExpr), "\\n", sep="")'
            )
            output = kw.get("output")
            if output:
                lines.append(
                    "write.table(data.frame(gene=colnames(datExpr), goodGene=gsg$goodGenes), "
                    "file=%s, sep=\"\\t\", quote=FALSE, row.names=FALSE)" % _rstr(output)
                )
            return [rscript, "-e", ";\n".join(lines)]

        # ---- run ----
        outdir = kw.get("outdir")
        if not outdir:
            raise RuntimeError("run 需要输出目录：--outdir <目录>")
        min_size = int(kw.get("min_module_size") or 30)
        cut_height = float(kw.get("merge_cut_height") if kw.get("merge_cut_height") is not None else 0.25)
        power_arg = kw.get("power")

        lines.append("powers <- c(1:10, seq(12, 20, by=2))")
        lines.append("sft <- pickSoftThreshold(datExpr, powerVector=powers, verbose=0)")
        if power_arg:
            lines.append(f"power <- {int(power_arg)}")
        else:
            lines.append("power <- sft$powerEstimate")
        lines.append("if (is.na(power) || power < 1) power <- 6")
        lines.append("adj <- adjacency(datExpr, power=power)")
        lines.append("TOM <- TOMsimilarity(adj)")
        lines.append("dissTOM <- 1 - TOM")
        lines.append("geneTree <- hclust(as.dist(dissTOM), method=\"average\")")
        lines.append(
            "dynamicMods <- cutreeDynamic(dendro=geneTree, distM=dissTOM, deepSplit=2, "
            "pamRespectsDendro=FALSE, minClusterSize=%d)" % min_size
        )
        lines.append("dynamicColors <- labels2colors(dynamicMods)")
        lines.append(
            "merged <- mergeCloseModules(datExpr, dynamicColors, cutHeight=%s, verbose=0)"
            % repr(cut_height)
        )
        lines.append("moduleColors <- merged$colors")
        lines.append("MEs <- merged$newMEs")
        lines.append(f"dir.create({_rstr(outdir)}, recursive=TRUE, showWarnings=FALSE)")
        lines.append(
            "write.table(data.frame(gene=colnames(datExpr), module=moduleColors), "
            "file=file.path(%s, \"gene_module_assignment.txt\"), sep=\"\\t\", quote=FALSE, "
            "row.names=FALSE)" % _rstr(outdir)
        )
        lines.append(
            "write.table(MEs, file=file.path(%s, \"module_eigengenes.txt\"), sep=\"\\t\", "
            "quote=FALSE, row.names=TRUE)" % _rstr(outdir)
        )

        trait = kw.get("trait")
        if trait:
            lines.append(
                "traitData <- read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", "
                "check.names=FALSE)" % _rstr(trait)
            )
            lines.append("moduleTraitCor <- cor(MEs, traitData, use=\"p\")")
            lines.append("moduleTraitPvalue <- corPvalueStudent(moduleTraitCor, nrow(datExpr))")
            lines.append(
                "write.table(moduleTraitCor, file=file.path(%s, "
                "\"module_trait_correlation.txt\"), sep=\"\\t\", quote=FALSE, row.names=TRUE)"
                % _rstr(outdir)
            )
            lines.append(
                "pdf(file.path(%s, \"module_trait_correlation.pdf\"), width=10, height=8)"
                % _rstr(outdir)
            )
            lines.append(
                "labeledHeatmap(Matrix=moduleTraitCor, xLabels=names(traitData), "
                "yLabels=names(MEs), ySymbols=names(MEs), colorLabels=FALSE, "
                "colors=blueWhiteRed(50), textMatrix=paste(signif(moduleTraitCor, 2), \"\\n(\", "
                "signif(moduleTraitPvalue, 1), \")\", sep=\"\"), setStdMargins=FALSE, "
                "cex.text=0.5, zlim=c(-1, 1), main=\"Module-trait relationships\")"
            )
            lines.append("dev.off()")

        lines.append(
            'cat("WGCNA_OK\\trun\\tmodules=", length(unique(moduleColors)), "\\tsamples=", '
            'nrow(datExpr), "\\tgenes=", ncol(datExpr), "\\tpower=", power, "\\n", sep="")'
        )
        return [rscript, "-e", ";\n".join(lines)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, default=None,
                   help="线程数（映射 allowWGCNAThreads；默认取 meta 建议值）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wgcna-skill",
        description="WGCNA native 技能驱动（Rscript 调用 goodSamplesGenes/adjacency/TOM/cutreeDynamic/mergeCloseModules）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("expr", help="表达矩阵（行基因、列样品，Tab 分隔，含首行样品名/首列基因名）")
    pr.add_argument("--outdir", required=True, help="输出目录（gene_module_assignment.txt 等）")
    pr.add_argument("--trait", help="性状/表型数据（样品×性状，可选；提供则做模块-性状关联）")
    pr.add_argument("--power", type=int, default=None, help="软阈值功率（默认由 pickSoftThreshold 自动估计）")
    pr.add_argument("--min-module-size", type=int, default=30, help="最小模块大小（默认 30）")
    pr.add_argument("--merge-cut-height", type=float, default=0.25,
                    help="相似模块合并阈值（默认 0.25，即相关性 > 0.75 合并）")
    _add_runtime_opts(pr)

    pc = sub.add_parser("check", help=SUBCOMMANDS["check"])
    pc.add_argument("expr", help="表达矩阵（行基因、列样品，Tab 分隔）")
    pc.add_argument("-o", "--output", default=None, help="质量检查报告输出表（可选）")
    _add_runtime_opts(pc)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = WGCNAPythonSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = WGCNAPythonSkill()
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
