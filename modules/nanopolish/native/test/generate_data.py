#!/usr/bin/env python3
"""生成 nanopolish native 测试用的合成输入。

nanopolish index/variants 等需要真实 fast5 信号与比对 BAM 才能跑真实计算，合成数据无法覆盖。
因此本脚本生成「可构造 argv 的占位输入 + 最小 VCF」，run_test.sh 在 nanopolish 未安装时退化为
「--list-commands/--schema 自省 + python 层 argv 构造断言（monkeypatch _resolve_binary）」。

产出：
  <outdir>/draft.fasta           最小参考基因组（2 条 contig）
  <outdir>/nanopore_reads.fastq  4 条 60bp 合成 reads
  <outdir>/reads.sorted.bam      文本占位（对照 BAM）
  <outdir>/variants.vcf          最小 VCF（vcf2fasta/phase-reads 输入解析用）
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

    (outdir / "draft.fasta").write_text(
        ">tig00000001\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
        ">tig00000002\n"
        "TTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n",
        encoding="utf-8",
    )
    reads = [
        ("read1", "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"),
        ("read2", "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA"),
        ("read3", "GGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAA"),
        ("read4", "TTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGG"),
    ]
    with open(outdir / "nanopore_reads.fastq", "w", encoding="utf-8") as fh:
        for name, seq in reads:
            fh.write(f"@{name}\n{seq}\n+\n{'I' * len(seq)}\n")

    (outdir / "reads.sorted.bam").write_text(
        "# PLACEHOLDER: nanopolish variants 需真实 minimap2 比对 + samtools sort/index 的 BAM\n",
        encoding="utf-8",
    )
    (outdir / "variants.vcf").write_text(
        "##fileformat=VCFv4.2\n"
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
        "tig00000001\t10\t.\tA\tG\t50\tPASS\t.\n",
        encoding="utf-8",
    )
    print(f"已生成 nanopolish 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
