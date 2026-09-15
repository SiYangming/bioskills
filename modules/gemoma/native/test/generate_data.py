#!/usr/bin/env python3
"""生成 gemoma native 测试用的合成输入。

GeMoMa 的真实预测需要参考/目标基因组与注释，合成数据无法覆盖真实计算；因此本脚本生成
「最小合法 FASTA/GFF 占位」，run_test.sh 在 GeMoMa 未安装时退化为「python 构造 argv 验证
命令构建不崩溃」。

产出：
  <outdir>/target.fasta         目标基因组 multi-FASTA（pipeline -t 输入）
  <outdir>/ref.fasta            参考基因组 multi-FASTA（Extractor/Pipeline -g 输入）
  <outdir>/ref.gff              参考注释 GFF（Extractor/Pipeline -a 输入）
  <outdir>/ref_proteins.fasta   参考蛋白序列占位（-p 输入）
  <outdir>/ref_cds.fasta        参考 CDS 序列占位（-c 输入）
  <outdir>/predicted.gff        预测注释占位（GAF -g 输入）
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

    fasta = ">seq1\nATGGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAA\n"
    (outdir / "target.fasta").write_text(fasta, encoding="utf-8")
    (outdir / "ref.fasta").write_text(fasta, encoding="utf-8")
    (outdir / "ref_proteins.fasta").write_text(
        ">ref_prot1\nMASTNPKPQRK\n", encoding="utf-8"
    )
    (outdir / "ref_cds.fasta").write_text(
        ">ref_cds1\nATGGCTAGCTAGCTAGCTAA\n", encoding="utf-8"
    )
    (outdir / "ref.gff").write_text(
        "##gff-version 3\n"
        "refseq1\tRef\tgene\t1\t60\t.\t+\t.\tID=gene1\n"
        "refseq1\tRef\tmRNA\t1\t60\t.\t+\t.\tID=mrna1;Parent=gene1\n"
        "refseq1\tRef\tCDS\t1\t60\t.\t+\t0\tID=cds1;Parent=mrna1\n",
        encoding="utf-8",
    )
    (outdir / "predicted.gff").write_text(
        "##gff-version 3\n"
        "seq1\tGeMoMa\tgene\t1\t60\t.\t+\t.\tID=g1\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
