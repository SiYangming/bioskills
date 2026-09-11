#!/usr/bin/env python3
"""生成 glimmerhmm（GlimmerHMM）native 测试用的合成真核基因组。

产出（<outdir> 下）：
  genome.fa   两条 contig（genome1=20000 bp、genome2=12000 bp）的合成基因组

说明：GlimmerHMM 需要一定长度序列才能给出预测；随机序列（固定种子）足以驱动
最小链路（断言 GFF3 头/序列区记录），不追求真实基因结构。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

DNA = "ACGT"


def rand_seq(rng: random.Random, n: int) -> str:
    return "".join(rng.choice(DNA) for _ in range(n))


def write_fasta(path: Path, records: list[tuple[str, str]]) -> None:
    with open(path, "w") as fh:
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

    rng = random.Random(42)
    write_fasta(outdir / "genome.fa", [
        ("genome1", rand_seq(rng, 20000)),
        ("genome2", rand_seq(rng, 12000)),
    ])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
