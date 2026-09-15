#!/usr/bin/env python3
"""ballgown native 标准入口驱动（Ballgown R 包，经 Rscript 调用）。

Ballgown 以 R/Bioconductor 函数库形态分发，无独立命令行二进制；本驱动用 Rscript 运行
「按参数生成到临时目录的 R 脚本」，脚本内部调用 ballgown() 读入 StringTie 输出目录，
gexpr() 过滤低表达后 stattest() 做基因 / 转录本水平差异表达分析。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze stringtie_out/ coldata.txt -o ballgown_out \
       --sample-pattern sample --covariate condition --threads 8
   python main.py check
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：Ballgown stattest 为单线程线性模型计算，--threads 映射为 BLAS 线程环境变量
（OMP/OPENBLAS/VECLIB/MKL_NUM_THREADS），仅影响底层矩阵运算（无多线程加速路径）。

前置：R（推荐 >= 4.2）且已安装 ballgown（BiocManager::install('ballgown') 或
conda install -c bioconda bioconductor-ballgown）；输入为 StringTie 组装的输出目录。
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
    "analyze": "Ballgown 差异表达分析（ballgown + stattest，基因/转录本水平各输出一张结果表）",
    "check": "校验 ballgown 包可加载并打印 packageVersion",
}

_BLAS = (
    'Sys.setenv(OMP_NUM_THREADS = "__THREADS__", OPENBLAS_NUM_THREADS = "__THREADS__", '
    'VECLIB_MAXIMUM_THREADS = "__THREADS__", MKL_NUM_THREADS = "__THREADS__")\n'
)

_R_ANALYZE = _BLAS + r'''suppressPackageStartupMessages(library(ballgown))
pheno_data <- read.table("__COLDATA__", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
pheno_data$condition <- factor(pheno_data$condition)
bg <- ballgown(dataDir = "__DATA_DIR__", samplePattern = "__SAMPLE_PATTERN__", pData = pheno_data)
bg_filt <- bg[rowSums(gexpr(bg)) > __MIN_EXPR__, ]
res_genes <- stattest(bg_filt, feature = "gene", covariate = "__COVARIATE__", adjustvars = NULL, getFC = TRUE)
res_transcripts <- stattest(bg_filt, feature = "transcript", covariate = "__COVARIATE__", adjustvars = NULL, getFC = TRUE)
write.table(res_genes, "__OUT_PREFIX__.gene.txt", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(res_transcripts, "__OUT_PREFIX__.transcript.txt", sep = "\t", quote = FALSE, row.names = FALSE)
cat("BALLGOWN_OK\n")
'''

_R_CHECK = r'''suppressPackageStartupMessages(library(ballgown))
cat("BALLGOWN_CHECK_OK packageVersion=", as.character(packageVersion("ballgown")), "\n", sep = "")
'''


def _render(template: str, **kw) -> str:
    out = template
    for k, v in kw.items():
        out = out.replace(f"__{k}__", str(v))
    return out


class BallgownSkill(base.SkillBase):
    software = "ballgown"
    binary = "Rscript"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "check":
            return [rscript, "-e", _R_CHECK.strip()]

        data_dir = kw.get("data_dir")
        coldata = kw.get("coldata")
        out_prefix = kw.get("output_prefix") or kw.get("output")
        if not data_dir:
            raise RuntimeError("analyze 需要 data_dir 参数（StringTie 输出目录；--help 查看）")
        if not coldata:
            raise RuntimeError("analyze 需要 coldata 参数（分组表；--help 查看）")
        if not out_prefix:
            raise RuntimeError("analyze 需要输出：-o/--output-prefix <prefix>（--help 查看）")

        script = _render(
            _R_ANALYZE,
            THREADS=int(threads),
            COLDATA=os.path.abspath(str(coldata)),
            DATA_DIR=os.path.abspath(str(data_dir)),
            SAMPLE_PATTERN=str(kw.get("sample_pattern") or "sample"),
            MIN_EXPR=int(kw.get("min_expr") if kw.get("min_expr") is not None else 1),
            COVARIATE=str(kw.get("covariate") or "condition"),
            OUT_PREFIX=os.path.abspath(str(out_prefix)),
        )
        tmpdir = self.make_tmpdir("ballgown_")
        script_path = Path(tmpdir) / "run_ballgown.R"
        script_path.write_text(script, encoding="utf-8")
        return [rscript, str(script_path)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ballgown-skill",
        description="Ballgown native 技能驱动（Rscript 调用 Ballgown 差异表达分析）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("data_dir", help="StringTie 输出目录（内含各样品 *_e_data.ctab 等）")
    pa.add_argument("coldata", help="分组表（Tab 分隔，首列样品 ID，含 condition 列）")
    pa.add_argument("-o", "--output-prefix", required=True,
                    help="输出前缀（写 <prefix>.gene.txt 与 <prefix>.transcript.txt）")
    pa.add_argument("--sample-pattern", default="sample", help="样品文件名匹配模式（默认 sample）")
    pa.add_argument("--covariate", default="condition", help="stattest 协变量列（默认 condition）")
    pa.add_argument("--min-expr", type=int, default=1, help="低表达过滤：rowSums(gexpr) > 阈值（默认 1）")
    _add_runtime_opts(pa)

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
        skill = BallgownSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BallgownSkill()
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
