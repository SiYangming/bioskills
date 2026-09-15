#!/usr/bin/env python3
"""生成 gblocks native 测试用的合成多序列比对。

Gblocks 输入为等长多序列比对（FASTA/PIR/NBRF）。本脚本生成一份小规模蛋白质比对与
一份密码子（核酸）比对，供 run_test.sh 做「参数构造验证」；若本机装了 Gblocks 再真实执行。

产出：
  <outdir>/sample.prot.aln    4 条等长蛋白质比对（FASTA，含少量空位）
  <outdir>/sample.codon.aln   4 条等长密码子（核酸）比对（长度 3 的倍数）
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

    prot = {
        "sp1": "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQ",
        "sp2": "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQ",
        "sp3": "MKTAYIAKQ--ISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQ",
        "sp4": "MKTAYIAKQRQISFVK-HFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAE-AVQ",
    }
    with (outdir / "sample.prot.aln").open("w", encoding="utf-8") as fh:
        for name, seq in prot.items():
            fh.write(f">{name}\n{seq}\n")

    codon = {
        "sp1": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCAT",
        "sp2": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCAT",
        "sp3": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCAT",
        "sp4": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCAT",
    }
    with (outdir / "sample.codon.aln").open("w", encoding="utf-8") as fh:
        for name, seq in codon.items():
            fh.write(f">{name}\n{seq}\n")

    print(f"已生成测试比对 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
