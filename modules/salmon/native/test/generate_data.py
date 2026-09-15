#!/usr/bin/env python3
"""生成 salmon native 测试用的合成输入。

salmon index/quant 需要真实索引与 reads（构建索引耗内存、耗时），合成数据无法覆盖真实计算。
因此本脚本生成「最小 FASTA / FASTQ / 定量目录占位」，run_test.sh 以 **argv 构造断言**
（monkeypatch 二进制解析）验证命令构建不崩溃，不依赖已安装的 salmon。

产出：
  <outdir>/transcripts.fa        最小转录本 FASTA（2 条）
  <outdir>/A1.1.fastq            最小左端 FASTQ
  <outdir>/A1.2.fastq            最小右端 FASTQ
  <outdir>/quantdir_A1/          quantmerge 输入占位目录
  <outdir>/quantdir_A2/          quantmerge 输入占位目录
"""
from __future__ import annotations

import sys
from pathlib import Path

FASTA = (
    ">TRINITY_DN_c1_g1_i1\n"
    "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC\n"
    ">TRINITY_DN_c1_g1_i2\n"
    "TTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n"
)

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


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "transcripts.fa").write_text(FASTA, encoding="utf-8")
    (outdir / "A1.1.fastq").write_text(FASTQ, encoding="utf-8")
    (outdir / "A1.2.fastq").write_text(FASTQ.replace("/1", "/2"), encoding="utf-8")
    for name in ("quantdir_A1", "quantdir_A2"):
        d = outdir / name
        d.mkdir(exist_ok=True)
        (d / "quant.sf").write_text(
            "Name\tLength\tEffectiveLength\tTPM\tNumReads\n"
            "TRINITY_DN_c1_g1_i1\t50\t46.0\t100.0\t10.0\n",
            encoding="utf-8",
        )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
