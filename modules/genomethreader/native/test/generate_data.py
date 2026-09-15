#!/usr/bin/env python3
"""生成 genomethreader native 测试用的合成输入。

gth 的真实剪接比对需要真实基因组 + cDNA/蛋白序列，合成数据无法覆盖真实计算；
因此本脚本生成「最小合法 FASTA/GFF3 占位」，run_test.sh 在 gth 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta        最小基因组 multi-FASTA（align -genomic 输入）
  <outdir>/cdna.fasta          最小 cDNA multi-FASTA（align -cdna 输入）
  <outdir>/protein.fasta       最小蛋白 multi-FASTA（align -protein 输入）
  <outdir>/intermediate.gff3   最小中间结果 GFF3（consensus/getseq 输入占位）
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
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "cdna.fasta").write_text(
        ">cdna1\nACGTACGTACGTACGTACGTACGT\n", encoding="utf-8"
    )
    (outdir / "protein.fasta").write_text(
        ">prot1\nMSTNPKPQRK TKRNTNRRPQ DVKFPGGGQI VGGVYYLLPR\n", encoding="utf-8"
    )
    # 最小中间结果 GFF3（consensus / getseq 输入占位；真实文件由 gth -intermediate 产生）
    (outdir / "intermediate.gff3").write_text(
        "##gff-version 3\n"
        "chr1\tgth\texon\t1\t30\t.\t+\t.\tID=exon1\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
