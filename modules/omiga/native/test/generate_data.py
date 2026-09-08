#!/usr/bin/env python3
"""omiga 测试数据生成（保持仓库轻量：只生成极小占位输入，不跑真实 QTL 分析）。

OmiGA 的 cis/trans/GWAS 分析需要真实 PLINK 基因型 + 表型数据才能实际计算；合成数据无法覆盖
真实关联运算。因此本脚本只生成占位的 PLINK 前缀文件（.bed/.bim/.fam）与表型/协变量文件，
供 run_test.sh 的 argv 构造断言与文档示例引用（标注「占位」，不可当真库使用）。
"""

from __future__ import annotations

import sys
from pathlib import Path


def main(outdir: str) -> None:
    work = Path(outdir)
    work.mkdir(parents=True, exist_ok=True)

    # PLINK 前缀占位（geno.bed/.bim/.fam —— 仅命名占位，bed 非真实二进制格式；
    # 真实分析请用 plink --make-bed 生成的标准 PLINK 1.9 二进制集）
    (work / "geno.bim").write_text(
        "1\trs1\t0\t1000\tA\tG\n"
        "1\trs2\t0\t2000\tC\tT\n",
        encoding="ascii",
    )
    (work / "geno.fam").write_text(
        "ind1\tind1\t0\t0\t1\t1\n"
        "ind2\tind2\t0\t0\t2\t1\n",
        encoding="ascii",
    )
    # .bed 占位（非真实二进制头；仅保证同名前缀文件齐全）
    (work / "geno.bed").write_bytes(b"\x00" * 16)

    # 表型（样本 ID + 表型值；真实格式以官方手册为准）
    (work / "pheno.txt").write_text(
        "FID\tIID\tTRAIT\n"
        "ind1\tind1\t1.2\n"
        "ind2\tind2\t0.8\n",
        encoding="ascii",
    )
    # 协变量占位
    (work / "covariates.txt").write_text(
        "FID\tIID\tCOV1\n"
        "ind1\tind1\t0.1\n"
        "ind2\tind2\t0.9\n",
        encoding="ascii",
    )

    print(f"[generate_data] wrote placeholder inputs to {work}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: generate_data.py <outdir>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1])
