#!/usr/bin/env python3
"""生成 MAFFT native 测试用的合成多序列 FASTA。

产出（<outdir>/input.fa）：
  6 条同源核酸序列（约 90~100 bp），由一条共同祖先经随机碱基替换 + 少量
  插入/缺失演化而来，模拟一组待多序列比对的同源基因片段。

说明：动态生成、体积 <2KB，仅用于 run_test.sh 的 mafft --auto 最小回归
（比对结果应为等长比对）；序列固定（seed=20260910），可重复断言。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 20260910
_ANCESTOR = (
    "ATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAG"
    "CATGCGTACGATCGTAGCTAGCTAGGCTAACGTTAGCATG"
    "GGCTAGCTAGCATCGATCGTAGCTAACGATCGATCGTACG"
)


def evolve(rng: random.Random, seq: str) -> str:
    """对祖先序列做随机替换 + 少量插入/缺失。"""
    bases = "ACGT"
    out: list[str] = []
    for ch in seq:
        r = rng.random()
        if r < 0.08:                      # 替换
            out.append(rng.choice([b for b in bases if b != ch]))
        elif r < 0.10:                    # 缺失（删一碱基）
            continue
        elif r < 0.12:                    # 插入（加一碱基）
            out.append(ch)
            out.append(rng.choice(bases))
        else:
            out.append(ch)
    return "".join(out)


def write_fasta(path: Path) -> None:
    rng = random.Random(_SEED)
    with open(path, "w") as fh:
        for i in range(1, 7):
            seq = evolve(rng, _ANCESTOR)
            fh.write(f">seq{i}\n")
            for j in range(0, len(seq), 60):
                fh.write(seq[j:j + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "input.fa")
    n = sum(1 for line in (outdir / "input.fa").read_text().splitlines() if line.startswith(">"))
    print(f"已生成合成多序列 FASTA -> {outdir / 'input.fa'}（{n} 条序列）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
