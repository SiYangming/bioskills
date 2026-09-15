#!/usr/bin/env python3
"""clusterprofiler native 标准入口驱动（clusterProfiler R 包，经 Rscript 调用）。

clusterProfiler 以 R 函数库形态分发（Bioconductor，无独立命令行二进制），本驱动用
`Rscript -e "<R 表达式>"` 直接调用 enrichGO()/enrichKEGG()/gseGO()（无需额外 .R 脚本）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py go   DEG_list.txt -o GO_enrichment_results.txt --ont ALL
   python main.py kegg DEG_list.txt -o KEGG_enrichment_results.txt --organism hsa
   python main.py gsea DESeq2_results.txt -o GSEA_results.txt --ont BP
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程（--threads）：映射 BiocParallel —— 富集调用注入
`BPPARAM=BiocParallel::MulticoreParam(workers=N)`，并在加载包前设置 OMP/OPENBLAS/
MKL/VECLIB 线程数环境变量；优先级：--threads > per_subcommand_threads > default_cpus。

前置：R >= 4.1 且已安装 clusterProfiler 与对应物种注释库（org.Hs.eg.db 等）；
或使用模块 README 中的官方 biocontainer 镜像
（quay.io/biocontainers/bioconductor-clusterprofiler）。
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
    "go": "GO 富集（enrichGO；ont=BP|CC|MF|ALL）",
    "kegg": "KEGG 通路富集（enrichKEGG；SYMBOL 自动转 ENTREZID）",
    "gsea": "GSEA 富集（gseGO；输入为基因 log2FC 排序表）",
}


def _rstr(value: object) -> str:
    """把 Python 字符串转成 R 双引号字符串字面量（转义反斜杠与双引号）。"""
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


class ClusterProfilerSkill(base.SkillBase):
    software = "clusterprofiler"
    binary = "Rscript"

    def _preamble(self, threads: int) -> list[str]:
        """公共前导：BLAS 线程环境变量 + BiocParallel mc.cores + 临时目录。"""
        t = str(threads)
        return [
            "suppressPackageStartupMessages(library(clusterProfiler))",
            "Sys.setenv(OMP_NUM_THREADS=%s, OPENBLAS_NUM_THREADS=%s, MKL_NUM_THREADS=%s, "
            "VECLIB_MAXIMUM_THREADS=%s)" % (_rstr(t), _rstr(t), _rstr(t), _rstr(t)),
            f"options(mc.cores={threads})",
            f"Sys.setenv(TMPDIR={_rstr(self.tmpdir)})",
        ]

    def _bpparam(self, threads: int) -> str:
        return f"BiocParallel::MulticoreParam(workers={threads})"

    def _load_orgdb(self, orgdb: str) -> str:
        return f"suppressPackageStartupMessages(library({_rstr(orgdb)}, character.only=TRUE))"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 `Rscript -e "<expr>"`；expr 依子命令拼装富集分析 R 代码。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        orgdb = str(kw.get("orgdb") or "org.Hs.eg.db")
        keytype = str(kw.get("keytype") or "SYMBOL").upper()
        pvalue = float(kw.get("pvalue") if kw.get("pvalue") is not None else 0.05)
        padjust = str(kw.get("padjust") or "BH").upper()
        qvalue = float(kw.get("qvalue") if kw.get("qvalue") is not None else 0.05)
        output = kw.get("output")
        if not output:
            raise RuntimeError(f"{subcommand} 需要输出：-o/--output <结果表>（--help 查看）")

        lines = self._preamble(threads)
        lines.append(self._load_orgdb(orgdb))

        if subcommand in ("go", "kegg"):
            gene_list = kw.get("gene_list")
            if not gene_list:
                raise RuntimeError(f"{subcommand} 需要基因列表：gene_list <文件，每行一个基因>")
            lines.append(f"genes <- readLines({_rstr(gene_list)})")
            lines.append("genes <- genes[nzchar(genes)]")

        if subcommand == "go":
            ont = str(kw.get("ont") or "ALL").upper()
            lines.append(
                "ego <- enrichGO(gene=genes, OrgDb=%s, keyType=%s, ont=%s, pAdjustMethod=%s, "
                "pvalueCutoff=%s, qvalueCutoff=%s, BPPARAM=%s)"
                % (orgdb, _rstr(keytype), _rstr(ont), _rstr(padjust),
                   repr(pvalue), repr(qvalue), self._bpparam(threads))
            )
            lines.append("res <- as.data.frame(ego)")
            lines.append(
                f"write.table(res, file={_rstr(output)}, sep=\"\\t\", quote=FALSE, row.names=FALSE)"
            )
            lines.append('cat("CLUSTERPROFILER_OK\\tgo\\tterms=", nrow(res), "\\n", sep="")')

        elif subcommand == "kegg":
            organism = str(kw.get("organism") or "hsa")
            if keytype == "ENTREZID":
                lines.append("entrez <- genes")
            else:
                lines.append(
                    "entrez <- clusterProfiler::bitr(genes, fromType=%s, toType=\"ENTREZID\", "
                    "OrgDb=%s)$ENTREZID" % (_rstr(keytype), orgdb)
                )
            lines.append(
                "ekk <- enrichKEGG(gene=entrez, organism=%s, pvalueCutoff=%s, pAdjustMethod=%s, "
                "qvalueCutoff=%s, BPPARAM=%s)"
                % (_rstr(organism), repr(pvalue), _rstr(padjust), repr(qvalue),
                   self._bpparam(threads))
            )
            lines.append("res <- as.data.frame(ekk)")
            lines.append(
                f"write.table(res, file={_rstr(output)}, sep=\"\\t\", quote=FALSE, row.names=FALSE)"
            )
            lines.append('cat("CLUSTERPROFILER_OK\\tkegg\\tterms=", nrow(res), "\\n", sep="")')

        else:  # gsea
            gene_rank = kw.get("gene_rank")
            if not gene_rank:
                raise RuntimeError("gsea 需要排序表：gene_rank <含 log2FC 的结果表>")
            rank_col = str(kw.get("rank_col") or "log2FoldChange")
            ont = str(kw.get("ont") or "BP").upper()
            lines.append(
                "res0 <- read.table(%s, header=TRUE, row.names=1, sep=\"\\t\", check.names=FALSE)"
                % _rstr(gene_rank)
            )
            lines.append(f"geneList <- res0[[{_rstr(rank_col)}]]")
            lines.append("names(geneList) <- rownames(res0)")
            lines.append("geneList <- sort(na.omit(geneList), decreasing=TRUE)")
            lines.append(
                "gse <- gseGO(geneList=geneList, OrgDb=%s, keyType=%s, ont=%s, pvalueCutoff=%s, "
                "BPPARAM=%s)"
                % (orgdb, _rstr(keytype), _rstr(ont), repr(pvalue), self._bpparam(threads))
            )
            lines.append("res <- as.data.frame(gse)")
            lines.append(
                f"write.table(res, file={_rstr(output)}, sep=\"\\t\", quote=FALSE, row.names=FALSE)"
            )
            lines.append('cat("CLUSTERPROFILER_OK\\tgsea\\tterms=", nrow(res), "\\n", sep="")')

        expr = ";\n".join(lines)
        return [rscript, "-e", expr]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("-o", "--output", required=True, help="富集结果表输出路径（Tab 分隔）")
    p.add_argument("--orgdb", default="org.Hs.eg.db",
                   help="物种注释库（默认 org.Hs.eg.db；如 org.Mm.eg.db）")
    p.add_argument("--keytype", default="SYMBOL", help="基因 ID 类型（默认 SYMBOL）")
    p.add_argument("--pvalue", type=float, default=0.05, help="p 值阈值（默认 0.05）")
    p.add_argument("--padjust", default="BH", help="p 值校正方法（默认 BH）")
    p.add_argument("--qvalue", type=float, default=0.05, help="q 值阈值（默认 0.05）")


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, default=None,
                   help="线程数（映射 BiocParallel MulticoreParam；默认取 meta 建议值）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="clusterprofiler-skill",
        description="clusterProfiler native 技能驱动（Rscript 调用 enrichGO/enrichKEGG/gseGO）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pg = sub.add_parser("go", help=SUBCOMMANDS["go"])
    pg.add_argument("gene_list", help="差异基因列表（每行一个基因名）")
    pg.add_argument("--ont", default="ALL", choices=["BP", "CC", "MF", "ALL"],
                    help="GO 本体（默认 ALL）")
    _add_common_opts(pg)
    _add_runtime_opts(pg)

    pk = sub.add_parser("kegg", help=SUBCOMMANDS["kegg"])
    pk.add_argument("gene_list", help="差异基因列表（每行一个基因名）")
    pk.add_argument("--organism", default="hsa", help="KEGG 物种代码（默认 hsa）")
    _add_common_opts(pk)
    _add_runtime_opts(pk)

    ps = sub.add_parser("gsea", help=SUBCOMMANDS["gsea"])
    ps.add_argument("gene_rank", help="基因 log2FC 排序表（含表头，首列基因名）")
    ps.add_argument("--rank-col", default="log2FoldChange", help="排序值列名（默认 log2FoldChange）")
    ps.add_argument("--ont", default="BP", choices=["BP", "CC", "MF"], help="GO 本体（默认 BP）")
    _add_common_opts(ps)
    _add_runtime_opts(ps)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = ClusterProfilerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ClusterProfilerSkill()
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
