#!/usr/bin/env python3
"""edger native 标准入口驱动（edgeR R 包，经 Rscript 调用）。

edgeR 以 R/Bioconductor 函数库形态分发，无独立命令行二进制；本驱动用 Rscript
运行「按参数生成到临时目录的 R 脚本」，脚本内部依次调用 DGEList() ->
calcNormFactors()（TMM）-> estimateDisp() -> exactTest() -> topTags()。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze gene.rawCount.matrix coldata.txt -o edgeR_results.txt \
       --pair control,treatment --threads 8
   python main.py norm gene.rawCount.matrix -o edgeR_norm_factors.txt
   python main.py check
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：edgeR 核心计算基本为单线程，--threads 映射为 BLAS 线程环境变量
（OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS），加速大矩阵运算。

前置：R（推荐 >= 4.2）且已安装 edgeR（BiocManager::install('edgeR') 或
conda install -c bioconda bioconductor-edger）。
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
    "analyze": "edgeR 差异表达分析（TMM 归一化 + estimateDisp + exactTest + topTags，输出结果表）",
    "norm": "TMM 归一化因子计算（calcNormFactors，输出 y$samples 归一化因子表）",
    "check": "校验 edgeR 包可加载并打印 packageVersion",
}

# BLAS 线程注入（edgeR 无多线程参数，经底层 BLAS 受益）
_BLAS = (
    'Sys.setenv(OMP_NUM_THREADS = "__THREADS__", OPENBLAS_NUM_THREADS = "__THREADS__", '
    'VECLIB_MAXIMUM_THREADS = "__THREADS__", MKL_NUM_THREADS = "__THREADS__")\n'
)

_R_ANALYZE = _BLAS + r'''suppressPackageStartupMessages(library(edgeR))
countData <- read.table("__COUNTS__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- read.table("__COLDATA__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
coldata <- coldata[colnames(countData), , drop = FALSE]
group <- factor(coldata$condition)
y <- DGEList(counts = countData, group = group)
keep <- rowSums(cpm(y) > __CPM_CUTOFF__) >= __MIN_SAMPLES__
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y)
y <- estimateDisp(y)
et <- exactTest(y, pair = c("__CTRL__", "__TREAT__"))
res <- topTags(et, n = Inf, adjust.method = "__ADJUST__")
write.table(res$table, "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("EDGER_OK\n")
'''

_R_NORM = _BLAS + r'''suppressPackageStartupMessages(library(edgeR))
countData <- read.table("__COUNTS__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
y <- DGEList(counts = countData)
y <- y[rowSums(y$counts) > 0, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y, method = "__METHOD__")
write.table(y$samples, "__OUTPUT__", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
cat("EDGER_NORM_OK\n")
'''

_R_CHECK = r'''suppressPackageStartupMessages(library(edgeR))
cat("EDGER_CHECK_OK packageVersion=", as.character(packageVersion("edgeR")), "\n", sep = "")
'''


def _render(template: str, **kw) -> str:
    out = template
    for k, v in kw.items():
        out = out.replace(f"__{k}__", str(v))
    return out


class EdgerSkill(base.SkillBase):
    software = "edger"
    binary = "Rscript"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "check":
            return [rscript, "-e", _R_CHECK.strip()]

        counts = kw.get("counts")
        output = kw.get("output")
        if not counts:
            raise RuntimeError(f"{subcommand} 需要 counts 参数（--help 查看）")
        if not output:
            raise RuntimeError(f"{subcommand} 需要输出：-o/--output <file>（--help 查看）")

        if subcommand == "analyze":
            coldata = kw.get("coldata")
            if not coldata:
                raise RuntimeError("analyze 需要 coldata 参数（分组表；--help 查看）")
            pair = str(kw.get("pair") or "control,treatment").split(",")
            if len(pair) != 2:
                raise RuntimeError("--pair 需为 control,treatment 两段（如 control,treatment）")
            script = _render(
                _R_ANALYZE,
                THREADS=int(threads),
                COUNTS=os.path.abspath(str(counts)),
                COLDATA=os.path.abspath(str(coldata)),
                CPM_CUTOFF=float(kw.get("cpm_cutoff") if kw.get("cpm_cutoff") is not None else 1),
                MIN_SAMPLES=int(kw.get("min_samples") if kw.get("min_samples") is not None else 3),
                CTRL=str(pair[0]).strip(),
                TREAT=str(pair[1]).strip(),
                ADJUST=str(kw.get("adjust") or "BH"),
                OUTPUT=os.path.abspath(str(output)),
            )
        else:  # norm
            method = str(kw.get("method") or "TMM")
            if method not in ("TMM", "TMMwsp", "RLE", "upperquartile", "none"):
                raise RuntimeError("--method 仅支持 TMM|TMMwsp|RLE|upperquartile|none")
            script = _render(
                _R_NORM,
                THREADS=int(threads),
                COUNTS=os.path.abspath(str(counts)),
                METHOD=method,
                OUTPUT=os.path.abspath(str(output)),
            )

        tmpdir = self.make_tmpdir("edger_")
        script_path = Path(tmpdir) / "run_edger.R"
        script_path.write_text(script, encoding="utf-8")
        return [rscript, str(script_path)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="edger-skill",
        description="edgeR native 技能驱动（Rscript 调用 edgeR 差异表达分析）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pa.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pa.add_argument("-o", "--output", required=True, help="差异表达结果输出文件（logFC/logCPM/PValue/FDR）")
    pa.add_argument("--pair", default="control,treatment", help="两组比较 control,treatment（默认 control,treatment）")
    pa.add_argument("--cpm-cutoff", type=float, default=1.0, help="低表达过滤 CPM 阈值（默认 1）")
    pa.add_argument("--min-samples", type=int, default=3, help="至少多少个样品满足 CPM 阈值（默认 3）")
    pa.add_argument("--adjust", default="BH", help="多重检验校正方法（默认 BH）")
    _add_runtime_opts(pa)

    pn = sub.add_parser("norm", help=SUBCOMMANDS["norm"])
    pn.add_argument("counts", help="raw count 矩阵（行=基因，列=样品，Tab 分隔，首列基因 ID）")
    pn.add_argument("-o", "--output", required=True, help="归一化因子输出文件（样品/lib.size/norm.factors）")
    pn.add_argument("--method", choices=["TMM", "TMMwsp", "RLE", "upperquartile", "none"],
                    default="TMM", help="归一化方法（默认 TMM）")
    _add_runtime_opts(pn)

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
        skill = EdgerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EdgerSkill()
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
