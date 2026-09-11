#!/usr/bin/env python3
"""生成 rnammer native 测试用的合成小基因组 FASTA。

产出（<outdir> 下）：
  genome.fa            合成小基因组（两条 contig，用于 scan 位置参数）
  genome.ecoli.fasta   同一序列（原核教学示例命名）

说明：RNAmmer 真预测需真实基因组；合成序列仅用于自省与（PATH 含 rnammer 时）最小链路
冒烟——验证命令构造（-S bac -multi -f/-h/-xml/-gff）与产物落盘。
"""
from __future__ import annotations

import sys
from pathlib import Path

BASES = "ACGT"


def synth(n: int, seed: int) -> str:
    """确定性伪随机序列（简单 LCG，可复现，无外部依赖）。"""
    x = seed
    out = []
    for _ in range(n):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        out.append(BASES[(x >> 16) & 3])
    return "".join(out)


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

    seqs = {"contig1": synth(3000, 42), "contig2": synth(1500, 7)}
    write_fasta(outdir / "genome.fa", seqs)
    write_fasta(outdir / "genome.ecoli.fasta", seqs)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
