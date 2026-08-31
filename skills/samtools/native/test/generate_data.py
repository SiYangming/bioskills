#!/usr/bin/env python3
"""生成 samtools native 测试用的合成数据。

产出：
  <outdir>/refs.fa      微型参考序列（两条 contig）
  <outdir>/reads.sam    比对到参考的合成 SAM
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


def write_fasta(path: Path) -> None:
    seqs = {
        "chr1": "ACGT" * 50,   # 200 bp
        "chr2": "TTGGCCAA" * 25,  # 200 bp
    }
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_sam(path: Path) -> None:
    header = (
        "@HD\tVN:1.6\tSO:unsorted\n"
        "@SQ\tSN:chr1\tLN:200\n"
        "@SQ\tSN:chr2\tLN:200\n"
    )
    # 4 条 read，2 条比对 chr1，2 条比对 chr2，其中 1 条未比对
    rows = [
        "read1\t0\tchr1\t1\t60\t10M\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF",
        "read2\t0\tchr1\t50\t60\t10M\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF",
        "read3\t0\tchr2\t1\t60\t10M\t*\t0\t0\tTTGGCCAATT\tFFFFFFFFFF",
        "read4\t4\t*\t0\t0\t*\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF",
    ]
    with open(path, "w") as fh:
        fh.write(header)
        fh.write("\n".join(rows) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "refs.fa")
    write_sam(outdir / "reads.sam")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
