#!/usr/bin/env python3
"""生成 augustus native 测试用的合成输入。

AUGUSTUS 的真实预测/训练需要真实基因组与注释，合成数据无法覆盖真实计算；因此本脚本生成
「最小合法 FASTA/GFF/GenBank/BAM 占位」，run_test.sh 在 augustus 未安装时退化为「python
构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta     最小基因组 multi-FASTA（predict / gff2gb 输入）
  <outdir>/hints.gff        最小 RNA-seq hints GFF（predict --hintsfile 输入）
  <outdir>/genes.gb         最小 GenBank 训练集占位（etraining / optimize 输入）
  <outdir>/annotation.gff3  最小 GFF3 注释（gff2gb 输入）
  <outdir>/rnaseq.bam       BAM 占位（bam2hints 输入）
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

    (outdir / "genome.fasta").write_text(
        ">chr1\n"
        "ATGGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAA\n"
        "ATGGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAA\n",
        encoding="utf-8",
    )
    (outdir / "hints.gff").write_text(
        "chr1\thints\tintron\t10\t30\t.\t+\t.\t\n", encoding="utf-8"
    )
    # 最小 GenBank 占位（真实训练集由 gff2gbSmallDNA.pl 产生）
    (outdir / "genes.gb").write_text(
        "LOCUS       chr1                      60 bp    DNA     linear   PLN 01-JAN-2020\n"
        "FEATURES             Location/Qualifiers\n"
        "     CDS             1..60\n"
        "                     /gene=\"g1\"\n"
        "ORIGIN\n"
        "        1 atggctagct agctagctag ctagctagct agctagctag ctagctagct agctagctaa\n"
        "//\n",
        encoding="utf-8",
    )
    (outdir / "annotation.gff3").write_text(
        "##gff-version 3\n"
        "chr1\ttest\tgene\t1\t60\t.\t+\t.\tID=gene1\n"
        "chr1\ttest\tmRNA\t1\t60\t.\t+\t.\tID=mrna1;Parent=gene1\n"
        "chr1\ttest\tCDS\t1\t60\t.\t+\t0\tID=cds1;Parent=mrna1\n",
        encoding="utf-8",
    )
    (outdir / "rnaseq.bam").write_text(
        "# PLACEHOLDER: bam2hints 需要真实 RNA-seq sorted BAM\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
