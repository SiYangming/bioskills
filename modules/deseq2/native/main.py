#!/usr/bin/env python3
"""deseq2 native 标准入口驱动（DESeq2 R 包，经 Rscript 调用）。

DESeq2 以 R/Bioconductor 函数库形态分发，无独立命令行二进制；本驱动用 Rscript
运行「按参数生成到临时目录的 R 脚本」，脚本内部依次调用
DESeqDataSetFromMatrix() -> DESeq() -> results()/vst()/rlog()。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze gene.rawCount.matrix coldata.txt -o DESeq2_results.txt \
       --design '~condition' --contrast condition,treatment,control --threads 8
   python main.py vst gene.rawCount.matrix coldata.txt -o vst_normalized_matrix.txt
   python main.py check
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：--threads 映射到 BiocParallel（register(MulticoreParam(n))），DESeq() 的多核
离散度估计即走该并行后端；同时设置 OMP/OPENBLAS/VECLIB/MKL 线程环境变量。

前置：R（推荐 >= 4.2）且已安装 DESeq2（BiocManager::install('DESeq2') 或
conda install -c bioconda bioconductor-deseq2）。
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
    "analyze": "DESeq2 差异表达分析（DESeqDataSetFromMatrix -> DESeq -> results，输出结果表）",
    "vst": "方差稳定转换（vst/rlog，导出归一化表达矩阵用于热图/聚类）",
    "check": "校验 DESeq2 包可加载并打印 packageVersion",
}

# 生成 R 脚本时统一替换的占位符风格为 __NAME__（R 代码含 {} 不能用 f-string）
_R_ANALYZE = r'''suppressPackageStartupMessages({library(DESeq2); library(BiocParallel)})
register(MulticoreParam(__THREADS__))
countData <- read.table("__COUNTS__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- read.table("__COLDATA__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- coldata[colnames(countData), , drop = FALSE]
coldata$condition <- factor(coldata$condition)
stopifnot(all(rownames(coldata) == colnames(countData)))
dds <- DESeqDataSetFromMatrix(countData = countData, colData = coldata, design = __DESIGN__)
keep <- rowSums(counts(dds) >= __MIN_COUNT__) >= __MIN_SAMPLES__
dds <- dds[keep, ]
dds <- DESeq(dds)
res <- results(dds, contrast = __CONTRAST__)
res <- res[order(res$padj), ]
write.table(as.data.frame(res), "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("DESEQ2_OK\n")
'''

_R_VST = r'''suppressPackageStartupMessages({library(DESeq2); library(BiocParallel)})
register(MulticoreParam(__THREADS__))
countData <- read.table("__COUNTS__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- read.table("__COLDATA__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- coldata[colnames(countData), , drop = FALSE]
coldata$condition <- factor(coldata$condition)
stopifnot(all(rownames(coldata) == colnames(countData)))
dds <- DESeqDataSetFromMatrix(countData = countData, colData = coldata, design = __DESIGN__)
dds <- DESeq(dds)
vsd <- __TRANSFORM__(dds, blind = __BLIND__)
write.table(assay(vsd), "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("DESEQ2_VST_OK\n")
'''

_R_CHECK = r'''suppressPackageStartupMessages(library(DESeq2))
cat("DESEQ2_CHECK_OK packageVersion=", as.character(packageVersion("DESeq2")), "\n", sep = "")
'''


def _render(template: str, **kw) -> str:
    out = template
    for k, v in kw.items():
        out = out.replace(f"__{k}__", str(v))
    return out


class Deseq2Skill(base.SkillBase):
    software = "deseq2"
    binary = "Rscript"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令生成 R 脚本（或 -e 表达式）并构造 Rscript 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "check":
            return [rscript, "-e", _R_CHECK.strip()]

        counts = kw.get("counts")
        coldata = kw.get("coldata")
        if not (counts and coldata):
            raise RuntimeError(f"{subcommand} 需要 counts、coldata 参数（--help 查看）")

        if subcommand == "analyze":
            output = kw.get("output")
            if not output:
                raise RuntimeError("analyze 需要输出：-o/--output <file>（--help 查看）")
            contrast = str(kw.get("contrast") or "condition,treatment,control").split(",")
            if len(contrast) != 3:
                raise RuntimeError("--contrast 需为 factor,treatment,control 三段（如 condition,treatment,control）")
            contrast_expr = "c(" + ", ".join(f'"{c.strip()}"' for c in contrast) + ")"
            script = _render(
                _R_ANALYZE,
                THREADS=int(threads),
                COUNTS=os.path.abspath(str(counts)),
                COLDATA=os.path.abspath(str(coldata)),
                DESIGN=str(kw.get("design") or "~condition"),
                MIN_COUNT=int(kw.get("min_count") if kw.get("min_count") is not None else 10),
                MIN_SAMPLES=int(kw.get("min_samples") if kw.get("min_samples") is not None else 3),
                CONTRAST=contrast_expr,
                OUTPUT=os.path.abspath(str(output)),
            )
        else:  # vst
            output = kw.get("output")
            if not output:
                raise RuntimeError("vst 需要输出：-o/--output <file>（--help 查看）")
            transform = str(kw.get("transform") or "vst")
            if transform not in ("vst", "rlog"):
                raise RuntimeError("--transform 仅支持 vst|rlog")
            blind = "TRUE" if kw.get("blind") else "FALSE"
            script = _render(
                _R_VST,
                THREADS=int(threads),
                COUNTS=os.path.abspath(str(counts)),
                COLDATA=os.path.abspath(str(coldata)),
                DESIGN=str(kw.get("design") or "~condition"),
                TRANSFORM=transform,
                BLIND=blind,
                OUTPUT=os.path.abspath(str(output)),
            )

        tmpdir = self.make_tmpdir("deseq2_")
        script_path = Path(tmpdir) / "run_deseq2.R"
        script_path.write_text(script, encoding="utf-8")
        return [rscript, str(script_path)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="deseq2-skill",
        description="DESeq2 native 技能驱动（Rscript 调用 DESeq2 差异表达分析）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pa.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pa.add_argument("-o", "--output", required=True, help="差异表达结果输出文件（含 baseMean/log2FoldChange/pvalue/padj）")
    pa.add_argument("--design", default="~condition", help="设计公式（默认 ~condition）")
    pa.add_argument("--contrast", default="condition,treatment,control",
                    help="对比（factor,treatment,control，默认 condition,treatment,control）")
    pa.add_argument("--min-count", type=int, default=10, help="低表达过滤阈值（默认 10）")
    pa.add_argument("--min-samples", type=int, default=3, help="至少多少个样品满足阈值（默认 3）")
    _add_runtime_opts(pa)

    pv = sub.add_parser("vst", help=SUBCOMMANDS["vst"])
    pv.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pv.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pv.add_argument("-o", "--output", required=True, help="归一化表达矩阵输出文件")
    pv.add_argument("--design", default="~condition", help="设计公式（默认 ~condition）")
    pv.add_argument("--transform", choices=["vst", "rlog"], default="vst", help="转换方法（默认 vst）")
    pv.add_argument("--blind", action="store_true", help="blind 转换（默认 FALSE，用设计信息）")
    _add_runtime_opts(pv)

    pc = sub.add_parser("check", help=SUBCOMMANDS["check"])
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射 BiocParallel）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Deseq2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Deseq2Skill()
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
