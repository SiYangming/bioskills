#!/usr/bin/env python3
"""生成 minimap2 native 测试用的合成数据。

产出：
  <outdir>/refs.fa   微型参考序列（两条 contig，各 ~1000 bp）
  <outdir>/reads.fa  3 条 reads，均为参考序列的精确子串（300 bp），保证能产生比对
"""
from __future__ import annotations

import random
import sys
from pathlib import Path


def _rand_seq(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_fasta(path: Path) -> None:
    rng = random.Random(42)  # 固定种子，输出可复现
    seqs = {
        "chr1": _rand_seq(1000, rng),
        "chr2": _rand_seq(1000, rng),
    }
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_reads(path: Path) -> None:
    """从参考序列中截取 300 bp 子串作为 reads（精确匹配，必出比对）。"""
    refs = {}
    with open(path.parent / "refs.fa") as fh:
        name, parts = None, []
        for line in fh:
            line = line.strip()
            if line.startswith(">"):
                if name:
                    refs[name] = "".join(parts)
                name = line[1:]
                parts = []
            else:
                parts.append(line)
        if name:
            refs[name] = "".join(parts)

    reads = {
        "read1": refs["chr1"][100:400],
        "read2": refs["chr1"][500:800],
        "read3": refs["chr2"][200:500],
    }
    with open(path, "w") as fh:
        for name, seq in reads.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "refs.fa")
    write_reads(outdir / "reads.fa")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
