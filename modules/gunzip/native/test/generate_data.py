#!/usr/bin/env python3
"""生成 gunzip native 测试用的最小合成输入。

产出（<outdir>/）：
  reads.fa.gz       微型序列（gzip 压缩，解压后为 FASTA）
  genes.gtf.gz      微型注释（gzip 压缩，解压后为 GTF 文本）
  counts.txt.gz     微型文本（gzip 压缩，解压后为普通文本）
"""
from __future__ import annotations

import gzip
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    payloads = {
        "reads.fa.gz": ">read1\nACGTACGTACGTACGTACGT\n>read2\nTTGGCCAATTGGCCAATTGG\n",
        "genes.gtf.gz": (
            "chr1\tsrc\ttranscript\t101\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
            "chr1\tsrc\texon\t101\t200\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        ),
        "counts.txt.gz": "gene\tcount\ng1\t10\ng2\t20\n",
    }
    for name, text in payloads.items():
        with gzip.open(outdir / name, "wt", encoding="utf-8") as fh:
            fh.write(text)

    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
