#!/usr/bin/env python3
"""生成 qiime2 native 测试用的合成输入（保持仓库轻量，不提交真实测序数据）。

产出（<outdir> 下）：
  01.emp-single-end-sequences/sequences.fastq.gz   极简 EMP multiplex fastq（gzip）
  01.emp-single-end-sequences/barcodes.fastq.gz    与 sequences 行数一致的 barcode fastq（gzip）
  sample-metadata.tsv                              最小 sample metadata（含 BarcodeSequence 列）
  empty.qza                                        QZA 占位（测试仅做命令构造/参数透传，不真实导入）
"""
from __future__ import annotations

import gzip
import sys
from pathlib import Path

SEQ = "@r1\nACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIII\n"
BAR = "@b1\nAGCTGATCG\n+\nIIIIIIIII\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    emp = outdir / "01.emp-single-end-sequences"
    emp.mkdir(parents=True, exist_ok=True)

    with gzip.open(emp / "sequences.fastq.gz", "wt", encoding="utf-8") as fh:
        fh.write(SEQ)
    with gzip.open(emp / "barcodes.fastq.gz", "wt", encoding="utf-8") as fh:
        fh.write(BAR)

    (outdir / "sample-metadata.tsv").write_text(
        "sample-id\tBarcodeSequence\tBodySite\tSubject\n"
        "sample1\tAGCTGATCG\tskin\tsubject1\n"
        "sample2\tTCGATCAGC\tgut\tsubject2\n",
        encoding="utf-8",
    )
    (outdir / "empty.qza").write_text("# PLACEHOLDER qza（仅用于 argv 构造测试）\n", encoding="utf-8")
    print(f"已生成 qiime2 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
