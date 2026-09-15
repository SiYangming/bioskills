#!/usr/bin/env python3
"""生成 sspace native 测试用的合成输入。

SSPACE 真正 scaffold 需要真实配对 reads 比对，合成数据无法覆盖真实计算。
因此本脚本生成「迷你 contigs + 文库文件 + 占位 fastq + 迷你 sorted SAM」，
run_test.sh 在 SSPACE 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta        迷你 contigs（scaffold 的 -s 输入）
  <outdir>/library.txt         文库文件（scaffold 的 -l 输入）
  <outdir>/fragment.1.fastq    占位 R1
  <outdir>/fragment.2.fastq    占位 R2
  <outdir>/reads.sorted.sam    read-name 排序 SAM（sam2tab 的输入，/1 /2 后缀）
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
        ">contig1\nACGTACGTACGTACGTACGTACGTACGTACGT\n"
        ">contig2\nTTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n"
        ">contig3\nACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "library.txt").write_text(
        "Lib1 bwa fragment.1.fastq fragment.2.fastq 177 0.43 FR\n"
        "Lib2 bwa jumping.1.fastq jumping.2.fastq 3014 0.67 RF\n",
        encoding="utf-8",
    )
    for mate in ("1", "2"):
        (outdir / f"fragment.{mate}.fastq").write_text(
            "# PLACEHOLDER: SSPACE scaffold 需要真实配对 corrected FASTQ\n"
            f"@read{mate}/1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n",
            encoding="utf-8",
        )
    # read-name 排序的迷你 SAM（供 sam2tab：R1/R2 相邻、列 3 非 *、列 4 起点）
    (outdir / "reads.sorted.sam").write_text(
        "@HD\tVN:1.6\tSO:queryname\n"
        "r1/1\t0\tcontig1\t1\t60\t16M\t*\t0\t0\tACGTACGTACGTACGT\tIIIIIIIIIIIIIIII\n"
        "r1/2\t0\tcontig2\t10\t60\t16M\t*\t0\t0\tTTTTGGGGCCCCAAAA\tIIIIIIIIIIIIIIII\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
