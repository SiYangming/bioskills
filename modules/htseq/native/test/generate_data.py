#!/usr/bin/env python3
"""生成 htseq native 测试用的合成输入。

htseq-count 需要真实比对 SAM/BAM 才能计数，合成数据无法覆盖真实解析。因此本脚本生成
「最小 SAM + 最小 GTF」，run_test.sh 在 htseq-count 未安装时退化为「用 python 构造 argv
验证命令构建不崩溃」。

产出：
  <outdir>/accepted_hits.sam   最小 SAM（2 条比对 + 1 条未比对）
  <outdir>/genome.gtf          最小 GTF（含 exon 特征与 gene_id 属性）
  <outdir>/genome.gff          同一注释的 GFF 副本（供 -f/-t 参数引用）
"""
from __future__ import annotations

import sys
from pathlib import Path

SAM = (
    "@HD\tVN:1.0\tSO:coordinate\n"
    "@SQ\tSN:chr1\tLN:1000\n"
    "r1\t0\tchr1\t120\t255\t20M\t*\t0\t0\tACGTACGTACGTACGTACGT\tIIIIIIIIIIIIIIIIIIII\tNH:i:1\n"
    "r2\t0\tchr1\t320\t255\t20M\t*\t0\t0\tACGTACGTACGTACGTACGT\tIIIIIIIIIIIIIIIIIIII\tNH:i:1\n"
    "r3\t4\t*\t0\t0\t*\t*\t0\t0\tACGTACGTACGTACGTACGT\tIIIIIIIIIIIIIIIIIIII\n"
)

GTF = (
    "# test annotation\n"
    'chr1\ttest\texon\t100\t200\t.\t+\t.\tgene_id "g1"; transcript_id "t1";\n'
    'chr1\ttest\texon\t300\t400\t.\t+\t.\tgene_id "g2"; transcript_id "t2";\n'
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "accepted_hits.sam").write_text(SAM, encoding="utf-8")
    (outdir / "genome.gtf").write_text(GTF, encoding="utf-8")
    (outdir / "genome.gff").write_text(GTF, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
