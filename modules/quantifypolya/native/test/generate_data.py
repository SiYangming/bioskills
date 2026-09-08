#!/usr/bin/env python3
"""生成 quantifypolya（QuantifyPolyA）native 测试用合成 poly(A) BED 数据。

QuantifyPolyA 输入为「每样本一个 .bed」（4 列无表头：
seqnames<TAB>strand<TAB>coord<TAB>score，coord 为 poly(A) 位点单点坐标，
score 为支持 read 数；文件名去 .bed 即样本名）。

产出（<outdir> 下）：
  bed/{brain1,brain2,uhr1,uhr2}.bed   4 样本 × 3 基因区 × 2 PAC（近端/远端簇）
  colData.tsv                         实验设计表（sample + condition 两列，
                                      行名与 bed 样本名一致，供组间 APA 度量 argv）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

# (样本名, 条件)：brain=Brain、uhr=UHR（对应官方 Human_MAQC 示例的命名惯例）
SAMPLES: list[tuple[str, str]] = [
    ("brain1", "Brain"), ("brain2", "Brain"),
    ("uhr1", "UHR"), ("uhr2", "UHR"),
]

# (基因区, 染色体, 链, 近端簇中心, 远端簇中心)
# 两簇中心相距 >= 200 bp（> Cluster.PolyA 默认 max.gapwidth=24，可分成不同 PAC）
GENES: list[tuple[str, str, str, int, int]] = [
    ("g1", "chr1", "+", 50500, 50900),
    ("g2", "chr1", "-", 200500, 200900),
    ("g3", "chr2", "+", 100500, 100900),
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    beddir = outdir / "bed"
    beddir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)

    for name, cond in SAMPLES:
        rows: list[tuple[str, str, int, int]] = []
        for _gid, chrom, strand, c1, c2 in GENES:
            # 条件偏好：Brain 富近端簇（proximal），UHR 富远端簇（distal）
            for center, bias in ((c1, 2.0 if cond == "Brain" else 0.6),
                                 (c2, 0.6 if cond == "Brain" else 2.0)):
                # 同一 PAC 内 1–4 个位点（散布在中心 ±12 bp，保证 gap<24 不跨簇合并）
                for coord in sorted(rng.randint(center - 12, center + 12)
                                    for _ in range(rng.randint(1, 4))):
                    score = max(1, int(rng.expovariate(1.0 / 5.0) * bias + 2))
                    rows.append((chrom, strand, coord, score))
        rows.sort()
        with open(beddir / f"{name}.bed", "w") as fh:
            for chrom, strand, coord, score in rows:
                fh.write(f"{chrom}\t{strand}\t{coord}\t{score}\n")

    # 实验设计表（首列样本名，须含 condition 列；与 R 端 colData 格式一致）
    with open(outdir / "colData.tsv", "w") as fh:
        fh.write("sample\tcondition\n")
        for name, cond in SAMPLES:
            fh.write(f"{name}\t{cond}\n")

    print(f"已生成 QuantifyPolyA 测试数据 -> {outdir}（bed/ + colData.tsv）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
