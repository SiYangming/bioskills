#!/usr/bin/env python3
"""生成 deseq2 native 测试用合成数据。

产出（<outdir> 下，均为 Tab 分隔）：
  gene.rawCount.matrix  6 样品 × 8 基因的 raw count 矩阵（首列 gene_id；g1 在 treatment 中高表达）
  coldata.txt           分组表（sample, condition；control×3 + treatment×3）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SAMPLES = [f"sample{i}" for i in range(1, 7)]
CONDITIONS = ["control"] * 3 + ["treatment"] * 3
GENES = [f"g{i}" for i in range(1, 9)]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(42)

    with open(outdir / "gene.rawCount.matrix", "w") as fh:
        fh.write("gene_id\t" + "\t".join(SAMPLES) + "\n")
        for gi, gene in enumerate(GENES):
            row = []
            for ci, cond in enumerate(CONDITIONS):
                base = 200 if (gi == 0 and cond == "treatment") else 50
                row.append(str(max(0, int(rng.gauss(base, base * 0.15)))))
            fh.write(gene + "\t" + "\t".join(row) + "\n")

    with open(outdir / "coldata.txt", "w") as fh:
        fh.write("sample\tcondition\n")
        for s, c in zip(SAMPLES, CONDITIONS):
            fh.write(f"{s}\t{c}\n")

    print(f"已生成 DESeq2 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
