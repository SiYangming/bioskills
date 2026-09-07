#!/usr/bin/env python3
"""生成 riborf（RibORF 2.0）native 测试用合成数据。

产出（<outdir> 下）：
  reads.fastq    4 条 28nt RPF 模拟 read（3' 带 CTGTAGGCAC 接头尾巴，可真实跑 removeAdapter.pl）
  genome.fa      微型基因组（2 条 contig）
  transcripts.genePred 微型转录本注释（UCSC genePred 格式，供 orfannotate/read_dist argv 验证）
"""
from __future__ import annotations

import sys
from pathlib import Path

ADAPTER = "CTGTAGGCAC"

READS = [
    "AUGGCCAAGCUGGAGAUCAACGGA" + "CUGA",
    "AUGGCCAAGCUGGAGAUCAACGGA" + "CGGA",
    "CCCGGGAAAACCCGGGAAAACCCG" + "ACGT",
    "UUUGGGCCCAAAUUUGGGCCCAA" + "TTAA",
]


def write_fastq(path: Path, reads: list[str]) -> None:
    with open(path, "w") as fh:
        for i, seq in enumerate(reads, start=1):
            fh.write(f"@read{i}\n{seq}{ADAPTER}\n+\n{'I' * (len(seq) + len(ADAPTER))}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    write_fastq(outdir / "reads.fastq", READS)

    with open(outdir / "genome.fa", "w") as fh:
        fh.write(">chr1\n" + "ACGT" * 100 + "\n>chr2\n" + "TTGGCCAA" * 50 + "\n")

    # genePred：name chrom strand txStart txEnd cdsStart cdsEnd exonCount exonStarts exonEnds
    with open(outdir / "transcripts.genePred", "w") as fh:
        fh.write("tx1\tchr1\t+\t0\t200\t10\t190\t1\t0,\t200,\n")
        fh.write("tx2\tchr2\t-\t0\t200\t10\t190\t1\t0,\t200,\n")

    print(f"已生成 RibORF 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
