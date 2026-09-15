#!/usr/bin/env python3
"""生成 varscan native 测试用的合成输入。

VarScan 需要真实 samtools mpileup 内容（含碱基/质量串）才能产出变异，合成数据无法覆盖
真实检测计算。因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv
验证命令构建不崩溃（monkeypatch _resolve_binary，不依赖已安装 varscan），并在已安装时
做 --version 冒烟。

产出：
  <outdir>/V1.mpileup           单样本 mpileup 占位（mpileup2snp/indel/cns 输入）
  <outdir>/paired.mpileup       肿瘤-正常 paired mpileup 占位（somatic/copynumber 输入）
  <outdir>/somatic_output.*     processSomatic 输入前缀占位
  <outdir>/variants.vcf         fpfilter 输入 VCF 占位
  <outdir>/tumor.bam            fpfilter 输入 BAM 占位
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

    (outdir / "V1.mpileup").write_text(
        "chr1\t100\tA\t10\tIIIIIIIIII\t~~~~~~~~~~\n"
        "chr1\t200\tC\t12\tIIIIIIIIIIII\t~~~~~~~~~~~~\n",
        encoding="utf-8",
    )
    (outdir / "paired.mpileup").write_text(
        "chr1\t100\tA\t10\tIIIIIIIIII\t~~~~~~~~~~\t20\tIIIIIIIIIIIIIIIIIIII\t~~~~~~~~~~~~~~~~~~~~\n",
        encoding="utf-8",
    )
    # processSomatic 的输入前缀（somatic 实际产出 .snp.vcf / .indel.vcf）
    (outdir / "somatic_output.snp.vcf").write_text(
        "##fileformat=VCFv4.1\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n",
        encoding="utf-8",
    )
    (outdir / "somatic_output.indel.vcf").write_text(
        "##fileformat=VCFv4.1\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n",
        encoding="utf-8",
    )
    (outdir / "variants.vcf").write_text(
        "##fileformat=VCFv4.1\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
        "chr1\t100\t.\tA\tG\t50\tPASS\t.\n",
        encoding="utf-8",
    )
    (outdir / "tumor.bam").write_text("# PLACEHOLDER: varscan fpfilter 需要真实 tumor BAM\n",
                                      encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
