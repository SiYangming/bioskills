#!/usr/bin/env python3
"""生成 flair native 测试用的合成输入。

flair collapse 需要真实 long-read 比对数据 + 参考基因组才能产出一致性转录本，
合成小型数据无法覆盖真实计算。因此本脚本生成「文本占位 + 说明」，
run_test.sh 在 flair 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」，
不执行真实 flair。

产出：
  <outdir>/sample.sorted.bam   文本占位（BAM->Bed12 输入）
  <outdir>/sample.bed12        最小 BED12 占位（annotate 输入）
  <outdir>/sample.gtf          最小 GTF 占位
  <outdir>/sample.fa           最小参考基因组占位（collapse 输入）
  <outdir>/sample.fastq.gz     文本占位（collapse reads 输入）
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

    (outdir / "sample.sorted.bam").write_text(
        "# PLACEHOLDER: flair bam2bed12 需要真实 long-read sorted BAM\n", encoding="utf-8"
    )
    # 最小 BED12：chr1 上一条 100bp 转录本，2 个外显子
    (outdir / "sample.bed12").write_text(
        "chr1\t100\t200\ttest_isoform1\t0\t+\t100\t200\t0\t2\t50,30,\t0,70,\n",
        encoding="utf-8",
    )
    (outdir / "sample.gtf").write_text(
        "# PLACEHOLDER GTF\nchr1\ttest\texon\t101\t150\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n",
        encoding="utf-8",
    )
    (outdir / "sample.fa").write_text(
        ">chr1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "sample.fastq.gz").write_text(
        "# PLACEHOLDER: 真实 raw reads FASTQ.GZ\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
