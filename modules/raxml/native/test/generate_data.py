#!/usr/bin/env python3
"""生成 raxml native 测试用的合成比对。

RAxML 输入为 Phylip（含 relaxed phylip）或 FASTA 比对。本脚本生成一份小规模 relaxed Phylip
核酸比对，供 run_test.sh 做参数构造验证；若本机装了 RAxML，只做 `-v` 版本冒烟（不做真实建树，
避免长耗时）。

产出：
  <outdir>/sample.phy   4 条等长核酸比对（relaxed Phylip，长度 60）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQS = {
    "sp1": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "sp2": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "sp3": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
    "sp4": "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    n = len(SEQS)
    length = len(next(iter(SEQS.values())))
    with (outdir / "sample.phy").open("w", encoding="utf-8") as fh:
        fh.write(f" {n} {length}\n")
        for name, seq in SEQS.items():
            fh.write(f"{name}  {seq}\n")

    print(f"已生成测试比对 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
