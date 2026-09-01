#!/usr/bin/env python3
"""动态生成 orfanage 测试用最小 GFF3 / FASTA。"""
import sys
from pathlib import Path

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
(out / "query.gff3").write_text(
    "##gff-version 3\n"
    "chr1\tTD\tgene\t100\t900\t.\t+\t.\tID=g1;Name=G1\n"
    "chr1\tTD\tCDS\t100\t900\t.\t+\t0\tParent=g1\n",
    encoding="utf-8",
)
(out / "ref.fa").write_text(">chr1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8")
(out / "tpl.fa").write_text(">tpl1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8")
print("test data generated")
