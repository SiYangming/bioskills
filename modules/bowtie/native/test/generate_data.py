#!/usr/bin/env python3
"""生成 bowtie（v1）native 测试用的合成数据。

产出（<outdir> 下）：
  refs.fa      微型参考序列（两条 contig，各 200 bp）
  reads_se.fq  单端 reads（从 chr1 截取的 30 bp 片段）
  reads_1.fq / reads_2.fq  双端 reads（同一参考的另一组片段）

说明：bowtie v1 默认报告模式等价 -k 1（每个 read 报告 1 条比对），
30 bp read 在周期参考 chr1 上的多重比对不会导致 read 被丢弃。
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ1 = "ACGT" * 50        # chr1: 200 bp
SEQ2 = "TTGGCCAA" * 25    # chr2: 200 bp

SE_STARTS = (0, 60, 120, 5)      # chr1 上 4 个单端 read 起点
PE_STARTS = (30, 90)              # chr1 上双端 read 起点（R1/R2 各一对）


def write_fasta(path: Path) -> None:
    seqs = {"chr1": SEQ1, "chr2": SEQ2}
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_fastq(path: Path, reads: list[str]) -> None:
    with open(path, "w") as fh:
        for i, seq in enumerate(reads, start=1):
            fh.write(f"@read{i}\n{seq}\n+\n{'I' * len(seq)}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "refs.fa")
    write_fastq(outdir / "reads_se.fq", [SEQ1[s:s + 30] for s in SE_STARTS])
    write_fastq(outdir / "reads_1.fq", [SEQ1[s:s + 30] for s in PE_STARTS])
    write_fastq(outdir / "reads_2.fq", [SEQ1[s + 50:s + 80] for s in PE_STARTS])
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
