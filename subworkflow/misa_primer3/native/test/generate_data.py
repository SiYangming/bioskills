#!/usr/bin/env python3
"""生成 misa_primer3 subworkflow 测试用的合成数据。

产出（<outdir> 下）：
  genome.fasta   单条序列（~1.3 kb），埋入 3 处相互间隔 >300 bp 的 SSR
                 （(AG)12 / (GAA)8 / (A)14，两侧显式加 C/T/G 避免重复单元被延长或移位），
                 保证每处 SSR 两侧都有 ≥300 bp 侧翼 —— 满足 misa_primer3.pl 默认
                 --flanking_length 300 + 产物 100-250 的引物设计条件。
  genome.one.fasta  仅含第一处 SSR 的短序列（~1.3 kb 截断版），用于更快的冒烟（可选）。

随机序列用固定种子生成（可复现）；不断言引物对数量（合成序列上的设计成功与否由 primer3 决定），
只断言「跑通 + 命中预期 SSR + 至少一条记录设计出引物」。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 42
FLANK = 300   # 每处 SSR 两侧的随机侧翼长度（>= misa_primer3.pl 默认 300）
GAP = 300     # SSR 之间的随机间隔（>> interruptions 100，避免并成复合 SSR）


def rand_seq(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_fasta(path: Path, name: str, seq: str) -> None:
    with open(path, "w", encoding="utf-8") as fh:
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

    # SSR 两侧显式加 C/T/G 之类不同碱基，避免 (AG)12 被前面的 A 顶成 (GA)12 等移位/延长
    seq = (
        rand_seq(FLANK, rng) + "C" + "AG" * 12 + "T"
        + rand_seq(GAP, rng) + "C" + "GAA" * 8 + "T"
        + rand_seq(GAP, rng) + "C" + "A" * 14 + "G"
        + rand_seq(FLANK, rng)
    )
    write_fasta(outdir / "genome.fasta", "chr1", seq)

    # 单 SSR 版（更快）：保留第一处 SSR 与两侧各 300 bp
    one = rand_seq(FLANK, rng) + "C" + "AG" * 12 + "T" + rand_seq(FLANK, rng)
    write_fasta(outdir / "genome.one.fasta", "chr1", one)
    print(f"已生成测试数据 -> {outdir}（genome.fasta {len(seq)} bp；genome.one.fasta {len(one)} bp）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
