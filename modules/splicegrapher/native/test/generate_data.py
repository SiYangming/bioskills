#!/usr/bin/env python3
"""生成 splicegrapher native 测试用的合成输入。

SpliceGrapher 真实运行需参考基因组 + 基因模型 + RNA-seq 比对并训练 SVM，合成数据无法覆盖真实计算。
因此本脚本生成「结构合法的最小文本输入」，run_test.sh 在脚本未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta     最小参考基因组（FASTA）
  <outdir>/genome.gff3      最小基因模型（GFF3）
  <outdir>/alignments.sam   最小 SAM（无 softclip，含 @HD/@SQ 头）
  <outdir>/classifiers.zip  分类器压缩包占位
  <outdir>/graphs/          剪接图目录占位（realignment_pipeline 输入）
  <outdir>/A.1.fastq / A.2.fastq  占位 FASTQ（realignment_pipeline 输入）
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    # 参考基因组（约 2 kb，单 contig）
    seq = ("ACGT" * 500)
    (outdir / "genome.fasta").write_text(f">chr1\n{seq}\n", encoding="utf-8")

    # 最小 GFF3 基因模型
    (outdir / "genome.gff3").write_text(
        "##gff-version 3\n"
        "chr1\ttest\tgene\t1\t300\t.\t+\t.\tID=gene1\n"
        "chr1\ttest\tmRNA\t1\t300\t.\t+\t.\tID=mrna1;Parent=gene1\n"
        "chr1\ttest\texon\t1\t150\t.\t+\t.\tID=exon1;Parent=mrna1\n"
        "chr1\ttest\texon\t200\t300\t.\t+\t.\tID=exon2;Parent=mrna1\n",
        encoding="utf-8",
    )

    # 最小 SAM：无 softclip（SpliceGrapher 要求），MAPQ 60，4 条 read
    sam_header = (
        "@HD\tVN:1.0\tSO:coordinate\n"
        "@SQ\tSN:chr1\tLN:2000\n"
    )
    read = "A" * 50
    qual = "I" * 50
    rows = []
    for i in range(4):
        pos = 1 + i * 10
        rows.append(f"r{i}\t0\tchr1\t{pos}\t60\t50M\t*\t0\t0\t{read}\t{qual}")
    (outdir / "alignments.sam").write_text(sam_header + "\n".join(rows) + "\n", encoding="utf-8")

    # 分类器压缩包占位（build_classifiers 输出名）
    with zipfile.ZipFile(outdir / "classifiers.zip", "w") as zf:
        zf.writestr("gt_don.cfg", "roc_score = 0.95\n")

    # 剪接图目录占位 + FASTQ 占位
    (outdir / "graphs").mkdir(exist_ok=True)
    (outdir / "graphs" / "chr1.gff").write_text(
        "chr1\ttest\tmRNA\t1\t300\t.\t+\t.\tID=mrna1\n", encoding="utf-8"
    )
    fq = "@r1\n" + "ACGT" * 12 + "\n+\n" + "I" * 48 + "\n"
    (outdir / "A.1.fastq").write_text(fq, encoding="utf-8")
    (outdir / "A.2.fastq").write_text(fq, encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
