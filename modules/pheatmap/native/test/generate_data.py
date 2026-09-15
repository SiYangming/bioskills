#!/usr/bin/env python3
"""生成 pheatmap native 测试用合成数据。

产出（<outdir> 下）：
  DEG_expression_matrix.txt 差异基因表达矩阵（行基因、列样品）
  sample_annotation.txt     样品列注释表（行样品、列 condition）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SAMPLES = ["control_1", "control_2", "control_3", "treatment_1", "treatment_2", "treatment_3"]
N_GENES = 30


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)

    header = "gene\t" + "\t".join(SAMPLES)
    rows = []
    for gi in range(N_GENES):
        base = 5.0 if gi < 15 else 9.0  # 前 15 个在 treatment 组上调
        vals = []
        for si, _ in enumerate(SAMPLES):
            shift = base + (3.0 if (gi < 15 and si >= 3) else 0.0)
            vals.append(f"{max(0.0, rng.gauss(shift, 0.6)):.3f}")
        rows.append(f"gene_{gi:03d}\t" + "\t".join(vals))
    (outdir / "DEG_expression_matrix.txt").write_text(
        header + "\n" + "\n".join(rows) + "\n", encoding="utf-8"
    )

    ann = ["sample\tcondition"]
    for s in SAMPLES:
        ann.append(f"{s}\t{'control' if s.startswith('control') else 'treatment'}")
    (outdir / "sample_annotation.txt").write_text("\n".join(ann) + "\n", encoding="utf-8")

    print(f"已生成 pheatmap 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
