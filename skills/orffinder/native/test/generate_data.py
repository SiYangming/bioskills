#!/usr/bin/env python3
"""生成 orffinder native 测试用的合成核酸 FASTA。

ORFfinder 需要真实核酸序列才能产出 ORF，合成数据无法覆盖真实计算，
因此本脚本生成一个小型、确定的核酸 FASTA（含 ORF 的模拟序列），
run_test.sh 在工具未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」，
不执行真实 ORFfinder；若二进制已安装则额外做 -version 冒烟。

产出：
  <outdir>/transcripts.fa   模拟核酸 FASTA（4 条，长度 300-1200 nt）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQUENCES = {
    "tx1": "ATG" + "GCTGTTGATGCATTGCCGAAGCGTGAA" * 16 + "TAA",      # ~540 nt
    "tx2": "ATG" + "TTCCCGTATGCGCAGGATTTAGCTGGT" * 30 + "TGA",      # ~960 nt
    "tx3": "ATG" + "GACGATCGTGTTGAAGCGTTAGATCCG" * 12 + "TAA",      # ~420 nt
    "tx4": "ATG" + "CGTTTAGCGCCAGATTTAGCGGTGATC" * 38 + "TAG",      # ~1200 nt
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with (outdir / "transcripts.fa").open("w", encoding="utf-8") as fh:
        for name, seq in SEQUENCES.items():
            fh.write(f">{name} sample={name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
