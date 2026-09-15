#!/usr/bin/env python3
"""生成 gapcloser native 测试用的合成输入。

GapCloser 真正补洞需要真实配对 reads 比对，合成数据无法覆盖真实计算。
因此本脚本生成「迷你 scaffold（含 N gap）+ SOAPdenovo 式 config + 占位 reads」，
run_test.sh 在 GapCloser 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fa         迷你 scaffold（含一处 N gap，fill 输入）
  <outdir>/config.txt        SOAPdenovo 式文库配置（-b）
  <outdir>/fragment.1.fastq  占位 R1（config 的 q1）
  <outdir>/fragment.2.fastq  占位 R2（config 的 q2）
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

    (outdir / "genome.fa").write_text(
        ">scaffold1\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTNNNNNNNNNNNNNNNNNNNN\n"
        "GGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCC\n",
        encoding="utf-8",
    )
    (outdir / "config.txt").write_text(
        "max_rd_len=150\n"
        "[LIB]\n"
        "avg_ins=300\n"
        "reverse_seq=0\n"
        "asm_flags=3\n"
        "rd_len_cutoff=150\n"
        "rank=1\n"
        "pair_num_cutoff=3\n"
        "map_len=32\n"
        "q1=fragment.1.fastq\n"
        "q2=fragment.2.fastq\n",
        encoding="utf-8",
    )
    for mate in ("1", "2"):
        (outdir / f"fragment.{mate}.fastq").write_text(
            "# PLACEHOLDER: GapCloser fill 需要真实配对 corrected FASTQ\n"
            f"@read{mate}/1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n",
            encoding="utf-8",
        )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
