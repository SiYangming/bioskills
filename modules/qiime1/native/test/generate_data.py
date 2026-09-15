#!/usr/bin/env python3
"""生成 qiime1 native 测试用的合成输入（保持仓库轻量，不提交真实测序数据）。

产出（<outdir> 下）：
  mapping.txt        最小 mapping 文件（#SampleID + BarcodeSequence…）
  seqs.fna           两条代表序列 FASTA（pick_otus / assign_taxonomy 用）
  R1.fastq.gz/R2.fastq.gz  极简双端 fastq（join_paired_ends 用）
  otu_map.txt        OTU map 占位（make_otu_table 用）
  taxonomy.txt       分类注释占位（assign_taxonomy 用）
  tree.tre           Newick 树占位（beta_diversity 用）
"""
from __future__ import annotations

import gzip
import sys
from pathlib import Path

FASTQ = "@r1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "mapping.txt").write_text(
        "#SampleID\tBarcodeSequence\tDescription\n"
        "Sample1\tAGCT\tgut\n"
        "Sample2\tTCGA\tgut\n",
        encoding="utf-8",
    )
    (outdir / "seqs.fna").write_text(
        ">seq1\nACGTACGTACGTACGTACGT\n>seq2\nACGTACGTACGTACGTACGA\n",
        encoding="utf-8",
    )
    for name in ("R1.fastq.gz", "R2.fastq.gz"):
        with gzip.open(outdir / name, "wt", encoding="utf-8") as fh:
            fh.write(FASTQ)
    (outdir / "otu_map.txt").write_text("0\tseq1\tseq2\n", encoding="utf-8")
    (outdir / "taxonomy.txt").write_text(
        "seq1\tk__Bacteria; p__Firmicutes\n", encoding="utf-8"
    )
    (outdir / "tree.tre").write_text("(seq1:0.1,seq2:0.1);\n", encoding="utf-8")
    print(f"已生成 qiime1 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
