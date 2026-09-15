#!/usr/bin/env python3
"""生成 clusterprofiler native 测试用合成数据。

产出（<outdir> 下）：
  DEG_list.txt       差异基因列表（每行一个基因名/符号，用于 enrichGO/enrichKEGG）
  DESeq2_results.txt 差异分析结果表（gene, log2FoldChange, padj；用于 gseGO 排序）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

GENES = [
    "TP53", "EGFR", "MYC", "KRAS", "BRCA1", "BRCA2", "PTEN", "RB1",
    "CDKN2A", "AKT1", "MAPK1", "MTOR", "PIK3CA", "SRC", "JUN", "FOS",
    "STAT3", "NFKB1", "RELA", "BCL2",
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)

    # 差异基因列表（取前 12 个）
    de_genes = GENES[:12]
    (outdir / "DEG_list.txt").write_text("\n".join(de_genes) + "\n", encoding="utf-8")

    # DESeq2 结果表（gene, log2FoldChange, padj）；部分基因显著上下调
    rows = []
    for i, g in enumerate(GENES):
        lfc = round(rng.uniform(-4, 4), 4)
        if i < 6:
            lfc = round(rng.uniform(1.5, 4), 4)      # 上调
        elif i < 12:
            lfc = round(rng.uniform(-4, -1.5), 4)    # 下调
        else:
            lfc = round(rng.uniform(-0.9, 0.9), 4)   # 不显著
        padj = round(rng.uniform(1e-6, 0.5), 8)
        rows.append(f"{g}\t{lfc}\t{padj}")
    (outdir / "DESeq2_results.txt").write_text(
        "gene\tlog2FoldChange\tpadj\n" + "\n".join(rows) + "\n", encoding="utf-8"
    )

    print(f"已生成 clusterProfiler 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
