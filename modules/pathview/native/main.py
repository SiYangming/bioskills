#!/usr/bin/env python3
"""pathview native 标准入口驱动（KEGG 通路富集可视化 R 包，经 Rscript 调用）。

pathview 以 R 函数库形态分发，无独立命令行二进制；本驱动用 Rscript 运行内嵌 R 驱动
（参数经临时 params.tsv 传递，规避 R 侧引号转义），调用 `pathview::pathview()` 把
基因/化合物数值（如差异表达 log2FC）映射到 KEGG 通路图。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py plot --kegg-ids ko00010 --gene-data study.txt \
       --species ko --out-dir kegg_out --out-suffix study1 --threads 4
   python main.py plot --kegg-ids ko00010,hsa04110 --gene-data ge.txt --cpd-data cpd.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

对应文档「十二、KEGG通路富集分析（pathview）」里的 `pathview.pl query.ko study.1.txt ...`：
本驱动是其结构化等价物（query.ko 的通路 id 走 --kegg-ids，study.N.txt 走 --gene-data）。

前置：R >= 4.2 且已安装 pathview（BiocManager::install('pathview')；
或使用模块 README 中的 quay.io/biocontainers/bioconductor-pathview 官方镜像）。
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
    "plot": "把基因/化合物数据映射到 KEGG 通路图（pathview::pathview，Rscript 驱动）",
}

# 内嵌 R 驱动：由 main.py 写入临时目录后经 Rscript 执行；参数经 params.tsv 传递。
_R_DRIVER = r'''
suppressPackageStartupMessages(library(pathview))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) stop("pathview driver: 需要 params.tsv")
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
read_data <- function(path) {
  if (is.null(path)) return(NULL)
  d <- read.delim(path, header = FALSE, row.names = 1, stringsAsFactors = FALSE, quote = "")
  x <- d[[1]]
  names(x) <- rownames(d)
  x
}
threads <- as.integer(gv("threads", "1"))
Sys.setenv(OMP_NUM_THREADS = threads, OPENBLAS_NUM_THREADS = threads)

gene.data <- read_data(gv("gene_data"))
cpd.data  <- read_data(gv("cpd_data"))
if (is.null(gene.data) && is.null(cpd.data)) stop("pathview: 需要 gene_data 或 cpd_data")

ids <- strsplit(gv("kegg_ids", ""), ",")[[1]]
ids <- ids[nzchar(ids)]
if (!length(ids)) stop("pathview: 需要 kegg_ids")

out.dir <- gv("out_dir", ".")
dir.create(out.dir, showWarnings = FALSE, recursive = TRUE)
species <- gv("species", "ko")
out.suffix <- gv("out_suffix", "pathview")

for (pid in ids) {
  cat("pathview:", pid, "\n")
  pathview::pathview(
    gene.data = gene.data, cpd.data = cpd.data,
    pathway.id = pid, species = species, out.suffix = out.suffix,
    out.dir = out.dir, kegg.dir = gv("kegg_dir", "."),
    gene.idtype = gv("gene_idtype", "KEGG"), cpd.idtype = gv("cpd_idtype", "KEGG"),
    discrete = as_bool("discrete", FALSE)
  )
}
cat("PATHVIEW_OK\n")
'''.strip()


class PathviewSkill(base.SkillBase):
    software = "pathview"
    binary = "Rscript"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """plot：写 params.tsv（含内嵌 R 驱动），返回 `Rscript -e <driver> <params>`。"""
        if subcommand != "plot":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        rscript = self._resolve_binary()

        kegg_ids = kw.get("kegg_ids")
        if not kegg_ids:
            raise RuntimeError("plot 需要 --kegg-ids（逗号分隔，如 ko00010 或 ko00010,hsa04110）")
        gene = kw.get("gene_data")
        cpd = kw.get("cpd_data")
        if not (gene or cpd):
            raise RuntimeError("plot 需要至少一个 --gene-data 或 --cpd-data")
        if kw.get("extra_args"):
            raise RuntimeError("plot 不支持 extra_args（参数已结构化，如需扩展请改 main.py 内嵌 R 驱动）")

        threads = self._effective_threads("plot", kw.get("threads"))
        pairs = [
            ("kegg_ids", str(kegg_ids)),
            ("species", str(kw.get("species") or "ko")),
            ("out_dir", os.path.abspath(str(kw.get("out_dir") or "."))),
            ("out_suffix", str(kw.get("out_suffix") or "pathview")),
            ("kegg_dir", os.path.abspath(str(kw.get("kegg_dir") or "."))),
            ("gene_idtype", str(kw.get("gene_idtype") or "KEGG")),
            ("cpd_idtype", str(kw.get("cpd_idtype") or "KEGG")),
            ("threads", str(int(threads))),
        ]
        if gene:
            pairs.append(("gene_data", os.path.abspath(str(gene))))
        if cpd:
            pairs.append(("cpd_data", os.path.abspath(str(cpd))))
        if kw.get("discrete"):
            pairs.append(("discrete", "TRUE"))

        tmpdir = self.make_tmpdir("pathview_")
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
        prog="pathview-skill",
        description="pathview native 技能驱动（Rscript 调用 pathview::pathview）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    pp.add_argument("--kegg-ids", required=True,
                    help="KEGG 通路 id（逗号分隔，如 ko00010 或 ko00010,hsa04110）")
    pp.add_argument("--gene-data", help="基因数据表（首列 gene id，次列数值）")
    pp.add_argument("--cpd-data", help="化合物数据表（首列 compound id，次列数值）")
    pp.add_argument("--species", default="ko", help="KEGG 物种/通路前缀（默认 ko）")
    pp.add_argument("--out-dir", default=".", help="输出目录（默认当前目录）")
    pp.add_argument("--out-suffix", default="pathview", help="输出文件名后缀（默认 pathview）")
    pp.add_argument("--gene-idtype", default="KEGG", help="gene.data 的 id 类型（默认 KEGG）")
    pp.add_argument("--cpd-idtype", default="KEGG", help="cpd.data 的 id 类型（默认 KEGG）")
    pp.add_argument("--discrete", action="store_true", help="离散型数据着色")
    pp.add_argument("--kegg-dir", default=".", help="KEGG kgml 缓存目录（默认当前目录）")
    pp.add_argument("--extra-args", help="保留字段（参数已结构化）")
    _add_runtime_opts(pp)

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
        skill = PathviewSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PathviewSkill()
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
