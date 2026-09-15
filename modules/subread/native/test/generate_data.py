#!/usr/bin/env python3
"""生成 subread native 测试用的合成输入。

featureCounts 需要真实比对 BAM 才能计数，subread-align/subjunc 需要真实索引与 reads 才能
比对，合成数据无法覆盖真实计算。因此本脚本生成「文本占位 + 最小可解析 GTF」，run_test.sh
在 subread 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.gtf          最小 GTF（含 gene_id/transcript_id，供 featureCounts 参数引用）
  <outdir>/sample1.bam         文本占位（featureCounts 输入之一）
  <outdir>/sample2.bam         文本占位（featureCounts 输入之二）
  <outdir>/subread_index       文本占位（subread-buildindex 索引前缀占位）
  <outdir>/reads_1.fq          最小 FASTQ（subread-align/subjunc mate1）
  <outdir>/reads_2.fq          最小 FASTQ（subread-align/subjunc mate2）
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

    (outdir / "genome.gtf").write_text(
        "# test gtf\n"
        'chr1\ttest\texon\t100\t200\t.\t+\t.\tgene_id "g1"; transcript_id "t1";\n'
        'chr1\ttest\texon\t300\t400\t.\t+\t.\tgene_id "g2"; transcript_id "t2";\n',
        encoding="utf-8",
    )
    for name in ("sample1.bam", "sample2.bam"):
        (outdir / name).write_text(
            "# PLACEHOLDER: featureCounts 需要真实比对 BAM\n", encoding="utf-8"
        )
    (outdir / "subread_index").write_text(
        "# PLACEHOLDER: subread-buildindex 生成的索引前缀\n", encoding="utf-8"
    )
    for r in ("reads_1.fq", "reads_2.fq"):
        (outdir / r).write_text(
            "@read1\nACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIII\n",
            encoding="utf-8",
        )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
