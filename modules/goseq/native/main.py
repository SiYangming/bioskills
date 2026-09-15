#!/usr/bin/env python3
"""goseq native 标准入口驱动（GO 富集 R 包，经 Rscript 调用）。

goseq 以 R 函数库形态分发，无独立命令行二进制；本驱动用 Rscript 运行内嵌 R 驱动
（参数经临时 params.tsv 传递，规避 R 侧引号转义），串联 `goseq::nullp()`（按基因长度
估计长度偏倚概率权重函数 PWF）+ `goseq::goseq()`（GO 类别过/欠代表检验），并计算 BH FDR。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py go --genes de_genes.txt --lengths gene_lengths.tsv \
       --gene2cat gene2go.tsv -o go_enrichment.tsv --method Wallenius --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

对应文档「十二」中 goseq 的安装与 GO 富集用法（Trinity run_GOseq.pl 的底层依赖）。

前置：R >= 4.2 且已安装 goseq（BiocManager::install('goseq')；
或使用模块 README 中的 quay.io/biocontainers/bioconductor-goseq 官方镜像）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "go": "GO 富集分析（nullp 长度偏倚校正 + goseq 过/欠代表检验，Rscript 驱动）",
}

# 内嵌 R 驱动：由 main.py 写入临时目录后经 Rscript 执行；参数经 params.tsv 传递。
_R_DRIVER = r'''
suppressPackageStartupMessages(library(goseq))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("goseq driver: 需要 params.tsv")
p <- read.delim(args[1], header = FALSE, sep = "\t", stringsAsFactors = FALSE,
                quote = "", col.names = c("k", "v"))
kv <- stats::setNames(as.list(p$v), p$k)
gv <- function(k, default = NULL) {
  v <- kv[[k]]
  if (is.null(v) || is.na(v) || identical(v, "")) default else v
}
as_bool <- function(k, default = FALSE) {
  v <- gv(k)
  if (is.null(v)) default else toupper(v) %in% c("TRUE", "T", "1", "YES")
}
threads <- as.integer(gv("threads", "1"))
Sys.setenv(OMP_NUM_THREADS = threads, OPENBLAS_NUM_THREADS = threads)

lens <- read.delim(gv("lengths"), header = FALSE, row.names = 1,
                   stringsAsFactors = FALSE, quote = "")
lengths_vec <- stats::setNames(as.numeric(lens[[1]]), rownames(lens))
if (any(is.na(lengths_vec))) stop("goseq: lengths 表存在非数值长度")

de <- trimws(readLines(gv("genes")))
de <- de[nzchar(de)]
gene.vector <- as.integer(names(lengths_vec) %in% de)
names(gene.vector) <- names(lengths_vec)
if (sum(gene.vector) == 0L) stop("goseq: 差异基因列表与 lengths 基因集无交集")

g2c <- read.delim(gv("gene2cat"), header = FALSE, stringsAsFactors = FALSE, quote = "")
gene2cat <- strsplit(g2c[[2]], "[,;]")
names(gene2cat) <- g2c[[1]]

method <- gv("method", "Wallenius")
tc <- gv("test_cats", "GO:CC,GO:BP,GO:MF")
test.cats <- if (is.null(tc) || !nzchar(tc)) NULL else strsplit(tc, ",")[[1]]
test.cats <- test.cats[nzchar(test.cats)]

pwf <- nullp(gene.vector, genome = NULL, id = NULL, bias.data = lengths_vec, plot.fit = FALSE)
res <- goseq(pwf, genome = NULL, id = NULL, gene2cat = gene2cat, test.cats = test.cats,
             method = method, use_genes_without_cat = as_bool("use_genes_without_cat", TRUE))
res$padj <- stats::p.adjust(res$over_represented_pvalue, method = "BH")
cat("goseq: DE genes =", sum(gene.vector), "/", length(gene.vector), "\n")
cat("goseq: categories tested =", nrow(res), "\n")
utils::write.table(res, file = gv("output"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("GOSEQ_OK\n")
'''.strip()


class GoseqSkill(base.SkillBase):
    software = "goseq"
    binary = "Rscript"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """go：写 params.tsv（含内嵌 R 驱动），返回 `Rscript -e <driver> <params>`。"""
        if subcommand != "go":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        rscript = self._resolve_binary()

        genes = kw.get("genes")
        lengths = kw.get("lengths")
        gene2cat = kw.get("gene2cat")
        output = kw.get("output")
        missing = [n for n, v in (("genes", genes), ("lengths", lengths),
                                  ("gene2cat", gene2cat), ("output", output)) if not v]
        if missing:
            raise RuntimeError(f"go 需要 --{'/--'.join(missing)}（--help 查看）")
        if kw.get("extra_args"):
            raise RuntimeError("go 不支持 extra_args（参数已结构化，如需扩展请改 main.py 内嵌 R 驱动）")

        threads = self._effective_threads("go", kw.get("threads"))
        method = str(kw.get("method") or "Wallenius")
        if method not in ("Wallenius", "Hypergeometric", "Repulsive"):
            raise RuntimeError("--method 仅支持 Wallenius | Hypergeometric | Repulsive")

        pairs = [
            ("genes", os.path.abspath(str(genes))),
            ("lengths", os.path.abspath(str(lengths))),
            ("gene2cat", os.path.abspath(str(gene2cat))),
            ("output", os.path.abspath(str(output))),
            ("method", method),
            ("test_cats", "" if kw.get("test_cats") is None else str(kw.get("test_cats"))),
            ("use_genes_without_cat", "TRUE" if kw.get("use_genes_without_cat", True) else "FALSE"),
            ("threads", str(int(threads))),
        ]

        tmpdir = self.make_tmpdir("goseq_")
        params = Path(tmpdir) / "params.tsv"
        params.write_text("".join(f"{k}\t{v}\n" for k, v in pairs), encoding="utf-8")
        return [rscript, "-e", _R_DRIVER, str(params)]

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="goseq-skill",
        description="goseq native 技能驱动（Rscript 调用 nullp + goseq 的 GO 富集）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pg = sub.add_parser("go", help=SUBCOMMANDS["go"])
    pg.add_argument("--genes", required=True, help="差异基因列表（每行一个 gene id）")
    pg.add_argument("--lengths", required=True, help="基因长度表（首列 gene id、次列长度）")
    pg.add_argument("--gene2cat", required=True, help="基因→GO 类别映射表（次列类别用 ; 或 , 分隔）")
    pg.add_argument("-o", "--output", required=True, help="GO 富集结果输出表（Tab 分隔）")
    pg.add_argument("--method", choices=["Wallenius", "Hypergeometric", "Repulsive"],
                    default="Wallenius", help="过/欠代表检验方法（默认 Wallenius）")
    pg.add_argument("--test-cats", default="GO:CC,GO:BP,GO:MF",
                    help="检验的类别空间（逗号分隔；留空则用 gene2cat 全部类别）")
    pg.add_argument("--no-use-genes-without-cat", dest="use_genes_without_cat",
                    action="store_false", help="不把无 GO 类别的基因计入背景")
    pg.add_argument("--extra-args", help="保留字段（参数已结构化）")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（透传 R 底层 BLAS 线程）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GoseqSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GoseqSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

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
