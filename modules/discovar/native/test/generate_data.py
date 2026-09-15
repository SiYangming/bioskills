#!/usr/bin/env python3
"""生成 discovar native 测试用的合成输入。

DISCOVAR 组装需要真实 BAM/参考，合成数据无法覆盖真实计算；本脚本生成「文本占位 +
说明」，供 run_test.sh 做 argv 构造断言（不真实执行 discovar）。

产出：
  <outdir>/sample-reads.bam        文本占位（READS= 输入）
  <outdir>/sample-genome.fasta     迷你参考 FASTA
  <outdir>/sample-genome.names     参考名列表（REFHEAD 配套）
  <outdir>/a.final/                组装输出目录占位（NhoodInfo DIR_IN=）
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

    (outdir / "sample-reads.bam").write_text(
        "# PLACEHOLDER: DISCOVAR 需要真实 BAM\n", encoding="utf-8")
    (outdir / "sample-genome.fasta").write_text(
        ">chr1\nACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8")
    (outdir / "sample-genome.names").write_text("chr1\n", encoding="utf-8")
    (outdir / "a.final").mkdir(exist_ok=True)
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
