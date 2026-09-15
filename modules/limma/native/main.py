#!/usr/bin/env python3
"""limma native 标准入口驱动（limma R 包，经 Rscript 调用）。

limma 以 R/Bioconductor 函数库形态分发，无独立命令行二进制；RNA-seq 场景常用
limma-voom 流程：DGEList() -> calcNormFactors() -> model.matrix() -> voom() ->
lmFit() -> eBayes() -> topTable()。本驱动用 Rscript 运行「按参数生成到临时目录的 R 脚本」。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze gene.rawCount.matrix coldata.txt -o limma_voom_results.txt \
       --design '~condition' --coef 2 --threads 8
   python main.py voom gene.rawCount.matrix coldata.txt -o limma_voom_matrix.txt
   python main.py check
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：limma/limma-voom 为线性模型计算，--threads 映射为 BLAS 线程环境变量
（OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS），加速矩阵运算。

前置：R（推荐 >= 4.2）且已安装 limma（BiocManager::install('limma') 或
conda install -c bioconda bioconductor-limma），voom 流程还需 edgeR。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "analyze": "limma-voom 差异表达分析（calcNormFactors + voom + lmFit + eBayes + topTable，输出结果表）",
    "voom": "voom 转换（导出 log2-CPM 归一化表达矩阵用于可视化/下游建模）",
    "check": "校验 limma 包可加载并打印 packageVersion",
}

_BLAS = (
    'Sys.setenv(OMP_NUM_THREADS = "__THREADS__", OPENBLAS_NUM_THREADS = "__THREADS__", '
    'VECLIB_MAXIMUM_THREADS = "__THREADS__", MKL_NUM_THREADS = "__THREADS__")\n'
)

_R_PREP = r'''suppressPackageStartupMessages({library(limma); library(edgeR)})
countData <- read.table("__COUNTS__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- read.table("__COLDATA__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- coldata[colnames(countData), , drop = FALSE]
coldata$condition <- factor(coldata$condition)
y <- DGEList(counts = countData)
keep <- rowSums(cpm(y) > __CPM_CUTOFF__) >= __MIN_SAMPLES__
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y)
design <- model.matrix(__DESIGN__, data = coldata)
'''

_R_ANALYZE = _BLAS + _R_PREP + r'''v <- voom(y, design, plot = FALSE)
fit <- lmFit(v, design)
fit <- eBayes(fit)
res <- topTable(fit, coef = __COEF__, number = Inf, adjust.method = "__ADJUST__")
write.table(res, "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("LIMMA_OK\n")
'''

_R_VOOM = _BLAS + _R_PREP + r'''v <- voom(y, design, plot = FALSE)
write.table(v$E, "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("LIMMA_VOOM_OK\n")
'''

_R_CHECK = r'''suppressPackageStartupMessages(library(limma))
cat("LIMMA_CHECK_OK packageVersion=", as.character(packageVersion("limma")), "\n", sep = "")
'''


def _render(template: str, **kw) -> str:
    out = template
    for k, v in kw.items():
        out = out.replace(f"__{k}__", str(v))
    return out


class LimmaSkill(base.SkillBase):
    software = "limma"
    binary = "Rscript"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "check":
            return [rscript, "-e", _R_CHECK.strip()]

        counts = kw.get("counts")
        coldata = kw.get("coldata")
        output = kw.get("output")
        if not (counts and coldata):
            raise RuntimeError(f"{subcommand} 需要 counts、coldata 参数（--help 查看）")
        if not output:
            raise RuntimeError(f"{subcommand} 需要输出：-o/--output <file>（--help 查看）")

        common = dict(
            THREADS=int(threads),
            COUNTS=os.path.abspath(str(counts)),
            COLDATA=os.path.abspath(str(coldata)),
            DESIGN=str(kw.get("design") or "~condition"),
            CPM_CUTOFF=float(kw.get("cpm_cutoff") if kw.get("cpm_cutoff") is not None else 1),
            MIN_SAMPLES=int(kw.get("min_samples") if kw.get("min_samples") is not None else 3),
            OUTPUT=os.path.abspath(str(output)),
        )
        if subcommand == "analyze":
            common["COEF"] = int(kw.get("coef") if kw.get("coef") is not None else 2)
            common["ADJUST"] = str(kw.get("adjust") or "BH")
            script = _render(_R_ANALYZE, **common)
        else:  # voom
            script = _render(_R_VOOM, **common)

        tmpdir = self.make_tmpdir("limma_")
        script_path = Path(tmpdir) / "run_limma.R"
        script_path.write_text(script, encoding="utf-8")
        return [rscript, str(script_path)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="limma-skill",
        description="limma native 技能驱动（Rscript 调用 limma-voom 差异表达分析）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pa.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pa.add_argument("-o", "--output", required=True, help="差异表达结果输出文件（logFC/AveExpr/t/P.Value/adj.P.Val/B）")
    pa.add_argument("--design", default="~condition", help="设计公式（默认 ~condition）")
    pa.add_argument("--coef", type=int, default=2, help="topTable 提取的系数列（默认 2）")
    pa.add_argument("--cpm-cutoff", type=float, default=1.0, help="低表达过滤 CPM 阈值（默认 1）")
    pa.add_argument("--min-samples", type=int, default=3, help="至少多少个样品满足 CPM 阈值（默认 3）")
    pa.add_argument("--adjust", default="BH", help="多重检验校正方法（默认 BH）")
    _add_runtime_opts(pa)

    pv = sub.add_parser("voom", help=SUBCOMMANDS["voom"])
    pv.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pv.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pv.add_argument("-o", "--output", required=True, help="voom log2-CPM 归一化矩阵输出文件")
    pv.add_argument("--design", default="~condition", help="设计公式（默认 ~condition）")
    pv.add_argument("--cpm-cutoff", type=float, default=1.0, help="低表达过滤 CPM 阈值（默认 1）")
    pv.add_argument("--min-samples", type=int, default=3, help="至少多少个样品满足 CPM 阈值（默认 3）")
    _add_runtime_opts(pv)

    pc = sub.add_parser("check", help=SUBCOMMANDS["check"])
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射 BLAS 线程）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = LimmaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LimmaSkill()
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
