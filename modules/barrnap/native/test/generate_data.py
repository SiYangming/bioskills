#!/usr/bin/env python3
"""生成 barrnap native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fa  微型合成基因组（两条 contig，各约 600–800 bp，随机碱基）

说明：barrnap 真实回归只断言 GFF3 头（##gff-version 3）与退出码——合成序列上的
rRNA 预测数不保证，因此测试不断言特征行（详见 run_test.sh）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 42
N_CONTIGS = 2
LENGTHS = (610, 780)


def rand_seq(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_fasta(path: Path, seqs: dict[str, str]) -> None:
    with open(path, "w") as fh:
        for name, seq in seqs.items():
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
    seqs = {f"contig{i:02d}": rand_seq(LENGTHS[i - 1], rng) for i in range(1, N_CONTIGS + 1)}
    write_fasta(outdir / "genome.fa", seqs)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
