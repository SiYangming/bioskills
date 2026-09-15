#!/usr/bin/env python3
"""生成 evidencemodeler native 测试用的合成输入。

EVM 真实运行需要基因组 + 多来源证据 GFF3（AUGUSTUS/GeneWise/PASA 等），合成数据无法覆盖
真实的权重整合计算。因此本脚本生成「最小 FASTA/GFF3/权重/分区占位」，run_test.sh 在 EVM
未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/genome.fasta              最小基因组
  <outdir>/gene_predictions.gff3     从头预测占位
  <outdir>/protein_alignments.gff3   蛋白比对占位
  <outdir>/transcript_alignments.gff3 转录本比对占位
  <outdir>/repeats.gff3              重复序列占位
  <outdir>/weights.txt               证据权重
  <outdir>/partitions_list.out       分区列表占位
  <outdir>/commands.list             待执行命令占位
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
        ">scaffold1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8"
    )
    (outdir / "gene_predictions.gff3").write_text(
        "##gff-version 3\n"
        "scaffold1\taugustus\tgene\t1\t18\t.\t+\t.\tID=g1\n",
        encoding="utf-8",
    )
    (outdir / "protein_alignments.gff3").write_text(
        "##gff-version 3\n"
        "scaffold1\tGeneWise\tprotein_match\t1\t18\t.\t+\t.\tID=p1\n",
        encoding="utf-8",
    )
    (outdir / "transcript_alignments.gff3").write_text(
        "##gff-version 3\n"
        "scaffold1\tpasa_transcript_alignments\ttranscript\t1\t18\t.\t+\t.\tID=t1\n",
        encoding="utf-8",
    )
    (outdir / "repeats.gff3").write_text(
        "##gff-version 3\n"
        "scaffold1\trepeat\tmatch\t30\t40\t.\t+\t.\tID=r1\n",
        encoding="utf-8",
    )
    (outdir / "weights.txt").write_text(
        "ABINITIO_PREDICTION\taugustus\t1\n"
        "PROTEIN\tGeneWise\t5\n"
        "TRANSCRIPT\tpasa_transcript_alignments\t10\n",
        encoding="utf-8",
    )
    (outdir / "partitions_list.out").write_text(
        "scaffold1:1-18\t10000\n", encoding="utf-8"
    )
    (outdir / "commands.list").write_text(
        "# EVM per-partition commands (placeholder)\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
