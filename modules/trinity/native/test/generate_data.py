#!/usr/bin/env python3
"""生成 trinity native 测试用的合成输入。

Trinity 组装需要真实 RNA-seq reads（计算量大、耗时分钟级），合成数据无法覆盖真实计算。
因此本脚本生成「最小 FASTQ / FASTA / 结果文件」，run_test.sh 以 **argv 构造断言**（monkeypatch
二进制解析）验证命令构建不崩溃，不依赖已安装的 Trinity。

产出：
  <outdir>/sample_left.fastq      最小左端 FASTQ（2 reads）
  <outdir>/sample_right.fastq     最小右端 FASTQ（2 reads）
  <outdir>/Trinity.fasta          含 TRINITY_DN_c1_g1_i1 命名的组装结果 FASTA（2 条）
  <outdir>/sample.genes.results   定量结果占位（abundance_matrix 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

FASTQ = (
    "@read1/1\n"
    "ACGTACGTACGTACGTACGTACGT\n"
    "+\n"
    "IIIIIIIIIIIIIIIIIIIIIIII\n"
    "@read2/1\n"
    "TTTTGGGGCCCCAAAATTTTGGGG\n"
    "+\n"
    "IIIIIIIIIIIIIIIIIIIIIIII\n"
)

TRINITY_FASTA = (
    ">TRINITY_DN_c1_g1_i1 len=24 path=[0:23]\n"
    "ACGTACGTACGTACGTACGTACGT\n"
    ">TRINITY_DN_c1_g1_i2 len=21 path=[0:20]\n"
    "ACGTACGTACGTACGTACGTA\n"
    ">TRINITY_DN_c2_g1_i1 len=24 path=[0:23]\n"
    "TTTTGGGGCCCCAAAATTTTGGGG\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "sample_left.fastq").write_text(FASTQ, encoding="utf-8")
    (outdir / "sample_right.fastq").write_text(FASTQ.replace("/1", "/2"), encoding="utf-8")
    (outdir / "Trinity.fasta").write_text(TRINITY_FASTA, encoding="utf-8")
    # 定量结果占位（abundance_estimates_to_matrix.pl 输入格式：制表符分隔，含 transcript_id/gene_id 两列）
    (outdir / "sample.genes.results").write_text(
        "transcript_id\tgene_id\tlength\teffective_length\texpected_count\tTPM\tFPKM\n"
        "TRINITY_DN_c1_g1_i1\tTRINITY_DN_c1_g1\t24\t20.0\t10.0\t100.0\t50.0\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
