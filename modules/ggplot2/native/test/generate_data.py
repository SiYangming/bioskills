#!/usr/bin/env python3
"""生成 ggplot2 native 测试用合成数据。

产出（<outdir> 下）：
  DESeq2_results.txt 差异分析结果表（gene, log2FoldChange, padj；用于火山图）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

N_GENES = 60


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)
    rows = []
    for i in range(N_GENES):
        if i < 15:            # 上调
            lfc = rng.uniform(1.2, 4.5)
            padj = rng.uniform(1e-8, 0.04)
        elif i < 30:          # 下调
            lfc = rng.uniform(-4.5, -1.2)
            padj = rng.uniform(1e-8, 0.04)
        else:                 # 不显著
            lfc = rng.uniform(-0.9, 0.9)
            padj = rng.uniform(0.05, 0.9)
        rows.append(f"gene_{i:03d}\t{lfc:.4f}\t{padj:.8f}")

    (outdir / "DESeq2_results.txt").write_text(
        "gene\tlog2FoldChange\tpadj\n" + "\n".join(rows) + "\n", encoding="utf-8"
    )
    print(f"已生成 ggplot2 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
