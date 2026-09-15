#!/usr/bin/env python3
"""生成 snpeff native 测试用的合成输入。

SnpEff 的 eff/build 需要真实数据库（FASTA + GTF 构建的 bin 索引）才能实际运行，
合成数据无法覆盖真实注释计算。因此本脚本生成「最小可解析的占位输入」，
run_test.sh 用 python 构造 argv 验证命令构建不崩溃（monkeypatch _resolve_binary，
不依赖已安装 snpeff），并在已安装时做 --version 冒烟。

产出：
  <outdir>/variants.vcf        最小 VCF（eff 输入占位）
  <outdir>/reference.fa        最小参考 FASTA（build 输入占位）
  <outdir>/genes.gtf           最小 GTF 注释（build 输入占位）
  <outdir>/snpEff.config       snpEff 配置占位（自定义数据库用）
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

    (outdir / "variants.vcf").write_text(
        "##fileformat=VCFv4.2\n"
        "##contig=<ID=chr1,length=1000>\n"
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
        "chr1\t100\t.\tA\tG\t50\tPASS\t.\n"
        "chr1\t200\t.\tC\tT\t60\tPASS\t.\n",
        encoding="utf-8",
    )
    (outdir / "reference.fa").write_text(
        ">chr1\n"
        + "ACGT" * 250 + "\n",
        encoding="utf-8",
    )
    (outdir / "genes.gtf").write_text(
        'chr1\ttest\texon\t100\t150\t.\t+\t.\tgene_id "g1"; transcript_id "t1";\n'
        'chr1\ttest\tCDS\t110\t140\t.\t+\t0\tgene_id "g1"; transcript_id "t1";\n',
        encoding="utf-8",
    )
    (outdir / "snpEff.config").write_text(
        "data.dir = ./data/\nmalassezia_sympodialis.genome : malassezia sympodialis\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
