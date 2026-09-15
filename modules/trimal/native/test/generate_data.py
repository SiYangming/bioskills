#!/usr/bin/env python3
"""生成 trimal native 测试用的合成多序列比对。

trimAl 输入为多序列比对（FASTA/Phylip/Clustal/Nexus 等）。本脚本生成一份小规模核酸比对
（含空位，便于修剪），供 run_test.sh 做参数构造验证；若本机装了 trimAl 再真实执行 trim。

产出：
  <outdir>/sample.aln   6 条等长核酸比对（FASTA，含空位列，长度 60）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQS = {
    "seq1": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "seq2": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "seq3": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "seq4": "ATGA---CCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "seq5": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCAT---",
    "seq6": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with (outdir / "sample.aln").open("w", encoding="utf-8") as fh:
        for name, seq in SEQS.items():
            fh.write(f">{name}\n{seq}\n")

    print(f"已生成测试比对 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
