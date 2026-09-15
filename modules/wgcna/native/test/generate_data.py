#!/usr/bin/env python3
"""生成 wgcna native 测试用合成数据。

产出（<outdir> 下）：
  expression_matrix.txt 基因表达矩阵（行基因、列样品；WGCNA 侧 t() 转样品×基因）
  trait_data.txt        性状/表型数据（行样品、列表型）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SAMPLES = [f"Sample_{i:02d}" for i in range(1, 13)]
N_GENES = 40


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)

    # 表达矩阵：基因×样品；前 20 个基因按模块模式生成（与样品分组相关），后 20 个随机
    header = "gene\t" + "\t".join(SAMPLES)
    rows = []
    for gi in range(N_GENES):
        if gi < 20:
            mod = gi % 2  # 两个共表达模块
            vals = [f"{rng.gauss(8 + 3 * mod, 0.5):.3f}" for _ in SAMPLES]
        else:
            vals = [f"{rng.gauss(6, 1.0):.3f}" for _ in SAMPLES]
        rows.append(f"gene_{gi:03d}\t" + "\t".join(vals))
    (outdir / "expression_matrix.txt").write_text(header + "\n" + "\n".join(rows) + "\n",
                                                  encoding="utf-8")

    # 性状数据：样品×性状
    trait_header = "sample\tcondition\tweight"
    trait_rows = []
    for i, s in enumerate(SAMPLES):
        cond = "treatment" if i >= 6 else "control"
        trait_rows.append(f"{s}\t{cond}\t{rng.uniform(18, 30):.2f}")
    (outdir / "trait_data.txt").write_text(trait_header + "\n" + "\n".join(trait_rows) + "\n",
                                           encoding="utf-8")

    print(f"已生成 WGCNA 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
