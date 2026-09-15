#!/usr/bin/env python3
"""生成 cufflinks native 测试用的合成输入。

Cufflinks 需要真实比对 BAM + 基因组才能组装/定量，合成数据无法覆盖真实计算；且软件已淘汰。
故本脚本生成「文本占位 + 说明」，run_test.sh 对六个子命令做「argv 构造验证」。

产出：
  <outdir>/sample.sorted.bam   文本占位（cufflinks/cuffquant 输入）
  <outdir>/sample.gtf          最小 GTF（cuffmerge/cuffcompare 输入）
  <outdir>/gtf_list.txt        GTF 列表（cuffmerge 输入）
  <outdir>/samples.txt         样本文件（cuffdiff/cuffnorm 输入）
  <outdir>/genome.fasta        最小基因组 FASTA（-s / -b 占位）
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
        "# PLACEHOLDER: cufflinks 需要真实 sorted BAM\n", encoding="utf-8"
    )
    (outdir / "sample.gtf").write_text(
        "chr1\tcufflinks\ttranscript\t100\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "chr1\tcufflinks\texon\t100\t200\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "chr1\tcufflinks\texon\t300\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n",
        encoding="utf-8",
    )
    (outdir / "gtf_list.txt").write_text(f"{outdir / 'sample.gtf'}\n", encoding="utf-8")
    (outdir / "samples.txt").write_text(f"{outdir / 'sample.sorted.bam'}\n", encoding="utf-8")
    (outdir / "genome.fasta").write_text(
        ">chr1\n" + ("ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n" * 4), encoding="utf-8"
    )
    print(f"已生成 cufflinks 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
