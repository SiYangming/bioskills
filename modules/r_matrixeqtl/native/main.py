#!/usr/bin/env python3
"""r_matrixeqtl native 标准入口驱动（Matrix eQTL R 包，经 Rscript 调用）。

Matrix eQTL 以 R 函数库形态分发，无独立命令行二进制，本驱动用 Rscript 运行
同目录 run_matrixeqtl.R（参数经临时 params.tsv 传递，规避 R 侧引号转义）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze snps.txt gene.txt -o eqtl_result.txt \
       --model linear --pv-threshold 1e-3 --threads 8
   python main.py analyze snps.txt gene.txt --output-prefix eqtl \
       --trans-p 1e-5 --cis-p 1e-3 --snps-loc snpspos.txt --gene-loc genepos.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

CLI 参数与 R 驱动（run_matrixeqtl.R）对齐：
  -o/--output（<output>；cis 另写 <output>.cis）与 --output-prefix（<p>_eQTL_trans.txt /
    <p>_eQTL_cis.txt）二选一；
  别名：--trans-p=--pv-threshold、--cis-p=--pv-threshold-cis、--snps-loc=--snpspos、
  --gene-loc=--genepos、--covariates-file=--covariates；
  --threads 取 auto（默认，不写 threads 键，由 R 驱动自动检测）或正整数；另支持 --pvalue-hist / --quiet。

前置：R >= 4.2 且已安装 MatrixEQTL（R install.packages('MatrixEQTL')；
或使用模块 README 中的 rocker/r-ver 容器/官方 biocontainer 老镜像）。
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
    "analyze": "Matrix_eQTL_main eQTL 关联分析（linear/anova/linear_cross + 可选 cis 分区）",
}


class RMatrixEQTLSkill(base.SkillBase):
    software = "r_matrixeqtl"
    binary = "Rscript"

    def _driver(self) -> Path:
        return _HERE / "run_matrixeqtl.R"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """analyze：写 params.tsv 并构造 `Rscript run_matrixeqtl.R <params>`。"""
        if subcommand != "analyze":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()

        # 必填：snps/gene；输出 -o/--output 与 --output-prefix 二选一
        snps = kw.get("snps")
        gene = kw.get("gene")
        output = kw.get("output")
        prefix = kw.get("output_prefix")
        if not (snps and gene):
            raise RuntimeError("analyze 需要 snps、gene 参数（--help 查看）")
        if not (output or prefix):
            raise RuntimeError("analyze 需要输出：-o/--output <f> 或 --output-prefix <p>（--help 查看）")

        # 参数文件（键<TAB>值）
        tmpdir = self.make_tmpdir("r_matrixeqtl_")
        params = Path(tmpdir) / "params.tsv"
        pairs = [
            ("snps", os.path.abspath(str(snps))),
            ("gene", os.path.abspath(str(gene))),
        ]
        if prefix:
            pairs.append(("output_prefix", os.path.abspath(str(prefix))))
        else:
            pairs.append(("output", os.path.abspath(str(output))))
        if kw.get("covariates"):
            pairs.append(("covariates", os.path.abspath(str(kw["covariates"]))))
        pairs.append(("model", str(kw.get("model", "linear"))))
        pairs.append(("pv_threshold", str(kw.get("pv_threshold", 1e-5))))
        pv_cis = float(kw.get("pv_threshold_cis") or 0)
        pairs.append(("pv_threshold_cis", str(pv_cis)))
        pairs.append(("cis_dist", str(int(kw.get("cis_dist") or 1000000))))
        if pv_cis > 0:
            for k in ("snpspos", "genepos"):
                v = kw.get(k)
                if not v:
                    raise RuntimeError(f"cis 模式（--pv-threshold-cis/--cis-p > 0）需要 {k} 位置表")
                pairs.append((k, os.path.abspath(str(v))))
        pairs.append(("slice_size", str(int(kw.get("slice_size") or 2000))))
        # threads：None / "auto" 不写 threads 键（由 R 驱动 auto_cores 自动检测）；整数则显式 pin
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            pairs.append(("threads", str(int(threads))))
        if kw.get("pvalue_hist"):
            pairs.append(("pvalue_hist", "TRUE"))
        if kw.get("quiet"):
            pairs.append(("verbose", "FALSE"))
        if kw.get("extra_args"):
            raise RuntimeError("analyze 不支持 extra_args（参数已结构化，如需扩展请改 run_matrixeqtl.R）")

        params.write_text("".join(f"{k}\t{v}\n" for k, v in pairs), encoding="utf-8")
        return [rscript, str(self._driver()), str(params)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="r-matrixeqtl-skill",
        description="Matrix eQTL native 技能驱动（Rscript 调用 Matrix_eQTL_main）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("snps", help="基因型矩阵（样本×SNP，Tab 分隔，首列 SNP id）")
    pa.add_argument("gene", help="基因表达矩阵（样本×基因，Tab 分隔，列顺序与 snps 一致）")
    pa.add_argument("-o", "--output", default=None,
                    help="显著 eQTL 输出文件（cis 启用时另写 <output>.cis；与 --output-prefix 二选一）")
    pa.add_argument("--output-prefix", default=None,
                    help="输出前缀（cis+trans 双输出：<p>_eQTL_trans.txt / <p>_eQTL_cis.txt；与 -o 二选一）")
    pa.add_argument("--covariates", "--covariates-file", help="协变量矩阵（可选；列顺序与 snps/gene 一致）")
    pa.add_argument("--model", choices=["linear", "anova", "linear_cross"], default="linear",
                    help="回归模型（默认 linear）")
    pa.add_argument("--pv-threshold", "--trans-p", type=float, default=1e-5,
                    help="trans/全距离显著性阈值（默认 1e-5）")
    pa.add_argument("--pv-threshold-cis", "--cis-p", type=float, default=0.0,
                    help="cis 阈值（>0 启用 cis 分区，需 --snpspos/--snps-loc、--genepos/--gene-loc）")
    pa.add_argument("--cis-dist", type=int, default=1000000, help="cis 窗口 bp（默认 1e6）")
    pa.add_argument("--snpspos", "--snps-loc", help="SNP 位置表（snpid chr pos）")
    pa.add_argument("--genepos", "--gene-loc", help="基因位置表（geneid chr left right）")
    pa.add_argument("--slice-size", type=int, default=2000, help="SlicedData 分片大小（默认 2000）")
    pa.add_argument("--pvalue-hist", action="store_true", help="记录 p 值直方图信息（默认关，省内存）")
    pa.add_argument("--quiet", action="store_true", help="静默（不打印进度，默认 verbose）")
    _add_runtime_opts(pa)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin）或 auto（省略 threads 键，交由 R 驱动自动检测）。"""
    v = str(value).strip().lower()
    if v == "auto":
        return "auto"
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=_threads_arg, default=None,
                   help="线程数：auto（默认，R 驱动按物理核数-1 检测）或正整数（如 8）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = RMatrixEQTLSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RMatrixEQTLSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
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
