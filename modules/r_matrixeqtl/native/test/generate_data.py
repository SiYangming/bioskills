#!/usr/bin/env python3
"""生成 r_matrixeqtl（Matrix eQTL）native 测试用合成数据。

产出（<outdir> 下，均为 Tab 分隔的 MatrixEQTL 输入格式，含首行样本名与首列 id）：
  snps.txt       12 样本 × 10 SNP（0/1/2 基因型；snp_01 与 gene_01 表达强相关）
  ge.txt         12 样本 × 6  基因表达（gene_01 = 2*snp_01 + 噪声）
  covariates.txt 12 样本 × 2  协变量（gender/age）
  snpspos.txt    SNP 位置表（snpid chr pos）
  genepos.txt    基因位置表（geneid chr left right）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SAMPLES = [f"Sam_{i:02d}" for i in range(1, 13)]
N_SNPS = 10
N_GENES = 6


def write_matrix(path: Path, row_ids: list[str], rows: list[list[str]]) -> None:
    with open(path, "w") as fh:
        fh.write("id\t" + "\t".join(SAMPLES) + "\n")
        for rid, row in zip(row_ids, rows):
            fh.write(rid + "\t" + "\t".join(row) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)

    # SNP 基因型：每 SNP 一行
    snp_ids = [f"snp_{i:02d}" for i in range(1, N_SNPS + 1)]
    snp_rows: list[list[str]] = []
    for si in range(N_SNPS):
        base = 1 if si == 0 else rng.randint(0, 2)
        snp_rows.append([str(min(2, max(0, base + rng.randint(-1, 1)))) for _ in SAMPLES])
    write_matrix(outdir / "snps.txt", snp_ids, snp_rows)

    # 基因表达：gene_01 与 snp_01 相关（2x + 噪声），便于低阈值真实回归出现显著关联
    geno = [int(v) for v in snp_rows[0]]
    gene_ids = [f"gene_{i:02d}" for i in range(1, N_GENES + 1)]
    ge_rows: list[list[str]] = []
    for gi in range(N_GENES):
        if gi == 0:
            ge_rows.append([f"{2 * g + rng.uniform(-0.2, 0.2):.3f}" for g in geno])
        else:
            ge_rows.append([f"{rng.uniform(0, 10):.3f}" for _ in SAMPLES])
    write_matrix(outdir / "ge.txt", gene_ids, ge_rows)

    # 协变量
    cov_rows = [
        [str(rng.randint(0, 1)) for _ in SAMPLES],
        [str(rng.randint(20, 60)) for _ in SAMPLES],
    ]
    write_matrix(outdir / "covariates.txt", ["gender", "age"], cov_rows)

    # 位置表（cis 分区测试用；snp_01 与 gene_01 落在 1e6 窗口内）
    with open(outdir / "snpspos.txt", "w") as fh:
        fh.write("snpid\tchr\tpos\n")
        for i, sid in enumerate(snp_ids):
            fh.write(f"{sid}\tchr1\t{100000 + i * 5000}\n")
    with open(outdir / "genepos.txt", "w") as fh:
        fh.write("geneid\tchr\tleft\tright\n")
        for i, gid in enumerate(gene_ids):
            fh.write(f"{gid}\tchr1\t{50000 + i * 10000}\t{50000 + i * 10000 + 2000}\n")

    print(f"已生成 MatrixEQTL 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
