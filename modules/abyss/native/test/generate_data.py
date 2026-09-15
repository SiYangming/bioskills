#!/usr/bin/env python3
"""生成 abyss native 测试用的合成输入。

ABySS 组装/独立 scaffolding 需要真实测序数据，合成数据无法覆盖真实计算；本脚本生成
「小体量合成占位」，供 run_test.sh 做 argv 构造断言与（stub 二进制下）CLI 真实执行链路
冒烟；真实组装冒烟在 PATH 中检测到 abyss-pe 时才执行（否则 [SKIP]）。

产出：
  <outdir>/fragment.1.fastq / fragment.2.fastq   PE 库占位
  <outdir>/jumping.1.fastq / jumping.2.fastq     Mate-pair 库占位
  <outdir>/E_coli-6.fa                           contigs FASTA 占位
"""
from __future__ import annotations

import sys
from pathlib import Path


def _fastq(path: Path, n: int) -> None:
    lines = []
    for i in range(1, n + 1):
        lines += [f"@read{i}", "ACGTACGTACGTACGT", "+", "IIIIIIIIIIIIIIII"]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    _fastq(outdir / "fragment.1.fastq", 2)
    _fastq(outdir / "fragment.2.fastq", 2)
    _fastq(outdir / "jumping.1.fastq", 2)
    _fastq(outdir / "jumping.2.fastq", 2)
    (outdir / "E_coli-6.fa").write_text(
        ">contig1\nACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
