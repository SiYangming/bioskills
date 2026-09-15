#!/usr/bin/env python3
"""生成 LASTZ native 测试用的合成输入。

LASTZ 比对需要真实基因组序列才能产出有意义结果，合成数据无法覆盖真实计算，
因此本脚本生成「结构合法的迷你 FASTA」，供 run_test.sh 做 argv 构造断言；
若本机已安装 lastz，还会用迷你序列跑一次真实冒烟。

产出：
  <outdir>/ref.fasta     目标/参考序列（FASTA，2 条 contig）
  <outdir>/query.fasta   查询序列（FASTA，2 条 contig）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"
LONG = SEQ + "TTGCAAGCTTAGCTAGCTAGCATCGATCGATCGATCGTAGCTAGCTAGCATCGATCGA"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "ref.fasta").write_text(
        f">ref1\n{SEQ}{SEQ}\n>ref2\n{LONG}\n", encoding="utf-8"
    )
    (outdir / "query.fasta").write_text(
        f">qry1\n{SEQ}{SEQ}\n>qry2\n{LONG}\n", encoding="utf-8"
    )
    print(f"已生成 LASTZ 测试合成数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
