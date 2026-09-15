#!/usr/bin/env python3
"""生成 genewise native 测试用的合成输入。

genewise 需要真实同源蛋白 + 基因组序列才能预测基因结构，合成数据无法覆盖真实计算。
因此本脚本生成「可被命令构造读取的迷你输入」，run_test.sh 在 genewise 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」（不依赖已安装二进制）。

产出：
  <outdir>/homolog.fasta   迷你同源蛋白 FASTA（protein）
  <outdir>/genome.fasta    迷你基因组 DNA FASTA（dna / --genome）
  <outdir>/genewise.gff    迷你 genewise 风格 GFF（gff2gff3 输入）
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

    (outdir / "homolog.fasta").write_text(
        ">homolog1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n",
        encoding="utf-8",
    )
    (outdir / "genome.fasta").write_text(
        ">chr1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAATTTCTTTTGTGAAATCTCACTTTTCTCGCCAG\n"
        "CTAGAAGAACGTCTTGGTCTTATTGAAGTTCAGTAA\n",
        encoding="utf-8",
    )
    # genewise GFF 最小占位（genewise 自带头部注释；gff2gff3 读它做转换）
    (outdir / "genewise.gff").write_text(
        "##gff-version 2\n"
        "chr1\tgenewise\tcds\t1\t30\t100.0\t+\t0\t\n"
        "chr1\tgenewise\tcds\t40\t66\t100.0\t+\t0\t\n",
        encoding="utf-8",
    )
    print(f"已生成测试迷你输入 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
