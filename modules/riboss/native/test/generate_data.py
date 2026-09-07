#!/usr/bin/env python3
"""生成 riboss native 测试用合成数据。

产出（<outdir> 下）：
  ann.gtf   微型基因注释（1 个基因 2 个转录本，含 CDS 注释）
  tx.fa     转录本 FASTA（与 ann.gtf 中转录本名对应，便于 orf_finder argv 验证）
说明：orf_finder/transcriptome_assembly 的真实执行依赖 UCSC 工具/stringtie/bedtools 等，
真实回归只在 riboss 环境可用时做 translate 自检；其余为 argv 构造验证。
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with open(outdir / "ann.gtf", "w") as fh:
        fh.write('##gff-version 3\n')
        fh.write('chr1\ttest\ttranscript\t1\t300\t.\t+\t.\tgene_id "g1"; transcript_id "tx1";\n')
        fh.write('chr1\ttest\texon\t1\t300\t.\t+\t.\tgene_id "g1"; transcript_id "tx1";\n')
        fh.write('chr1\ttest\tCDS\t10\t280\t.\t+\t0\tgene_id "g1"; transcript_id "tx1";\n')
        fh.write('chr1\ttest\ttranscript\t400\t700\t.\t-\t.\tgene_id "g1"; transcript_id "tx2";\n')
        fh.write('chr1\ttest\texon\t400\t700\t.\t-\t.\tgene_id "g1"; transcript_id "tx2";\n')

    # 含 ATG...TGA 完整 ORF 的转录本序列
    with open(outdir / "tx.fa", "w") as fh:
        fh.write(">tx1\n" + ("ATGGCCTAA" * 30) + "\n")
        fh.write(">tx2\n" + ("ATGGCCTAA" * 30) + "\n")

    print(f"已生成 riboss 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
