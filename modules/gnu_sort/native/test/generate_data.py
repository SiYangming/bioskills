#!/usr/bin/env python3
"""生成 gnu_sort native 测试用的最小合成输入。

产出（<outdir>/）：
  reads.sam   微型 SAM（4 条 read，未排序）
  genes.gtf   微型注释（跨 chr1/chr2，未排序）
  counts.txt  微型数值文本（供 -n -k1 数值排序）
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

    # SAM：read2 位于 chr1:50，read1 位于 chr1:1 —— 坐标排序后 read1 在前
    (outdir / "reads.sam").write_text(
        "@HD\tVN:1.6\tSO:unsorted\n"
        "@SQ\tSN:chr1\tLN:200\n"
        "read2\t0\tchr1\t50\t60\t10M\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF\n"
        "read1\t0\tchr1\t1\t60\t10M\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF\n"
        "read4\t4\t*\t0\t0\t*\t*\t0\t0\tACGTACGTAC\tFFFFFFFFFF\n"
        "read3\t0\tchr2\t1\t60\t10M\t*\t0\t0\tTTGGCCAATT\tFFFFFFFFFF\n"
    )

    (outdir / "genes.gtf").write_text(
        "chr2\tsrc\ttranscript\t501\t700\t.\t-\t.\tgene_id \"g2\"; transcript_id \"t2\";\n"
        "chr1\tsrc\ttranscript\t101\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "chr2\tsrc\texon\t501\t600\t.\t-\t.\tgene_id \"g2\"; transcript_id \"t2\";\n"
        "chr1\tsrc\texon\t101\t200\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
    )

    (outdir / "counts.txt").write_text("30\n10\n20\n")

    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
