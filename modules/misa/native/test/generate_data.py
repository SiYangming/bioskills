#!/usr/bin/env python3
"""生成 misa native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fasta        合成基因组 FASTA（2 条序列，埋入已知 SSR，便于断言命中）：
                        chr1：随机 120 bp + C + (AG)12 + T + 随机 120 bp
                        chr2：随机 80 bp + C + (A)12 + G + 随机 120 bp + C + (GAA)7 + T + 随机 80 bp
                       SSR 两侧显式加不同碱基（C/T、G/T），避免重复单元被相邻碱基延长或移位
                       （如 AG 重复被前面的 A 顶成 GA），保证基序/重复数可稳定断言；
                       chr2 两处 SSR 间距 > interruptions(100)，不会并成复合 SSR。
  custom.misa.ini     自定义 misa.ini（GFF: true + 关掉单碱基类，用于 --ini / --gff 路径）

随机序列用固定种子生成（可复现）；真实回归只断言 misa.pl 运行成功且命中预期基序，
不断言复合 SSR（c / c*）类型划分（与随机侧翼有关）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 20200910
FLANK = 120


def rand_seq(length: int, rng: random.Random) -> str:
    """GC 适中（各碱基等概率）的随机 DNA，避免与埋入 SSR 混淆。"""
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_fasta(path: Path, records: list[tuple[str, str]]) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        for name, seq in records:
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)

    chr1 = rand_seq(FLANK, rng) + "C" + "AG" * 12 + "T" + rand_seq(FLANK, rng)
    chr2 = (rand_seq(80, rng) + "C" + "A" * 12 + "G" + rand_seq(120, rng)
            + "C" + "GAA" * 7 + "T" + rand_seq(80, rng))
    write_fasta(outdir / "genome.fasta", [("chr1", chr1), ("chr2", chr2)])

    # 自定义 ini：GFF: true（逐序列 .gff，此时不产出 .misa）+ 关闭单碱基类
    (outdir / "custom.misa.ini").write_text(
        "definition(unit_size,min_repeats):          2-6 3-5 4-5 5-5 6-5\n"
        "interruptions(max_difference_for_2_SSRs):   50\n"
        "GFF:                                        true\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
