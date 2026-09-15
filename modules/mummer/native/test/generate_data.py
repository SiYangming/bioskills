#!/usr/bin/env python3
"""生成 MUMmer v4 native 测试用的合成输入。

MUMmer 的 nucmer/para_nucmer 需要真实基因组序列才能产出比对，合成数据无法覆盖真实计算，
因此本脚本生成「结构合法的最小合成文件」，供 run_test.sh 做 argv 构造断言；若本机已安装
MUMmer（delta-filter / show-coords），还会用合成 delta 做一次真实冒烟。

产出：
  <outdir>/ref.fasta     参考序列（FASTA，2 条 contig）
  <outdir>/qry.fasta     查询序列（FASTA，2 条 contig）
  <outdir>/out.delta     最小合法 delta 比对文件（供 delta-filter / show-coords / mummerplot）
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
    (outdir / "qry.fasta").write_text(
        f">qry1\n{SEQ}{SEQ}\n>qry2\n{LONG}\n", encoding="utf-8"
    )
    # 最小 delta：header 两行 + 每对 ref/qry 一个 '>' 行 + alignment 记录 + '0' 终止
    (outdir / "out.delta").write_text(
        "ref.fasta qry.fasta\n"
        "NUCMER\n"
        ">ref1 qry1 128 128\n"
        "1 128 1 128 4 4 0 0\n"
        "0\n",
        encoding="utf-8",
    )
    print(f"已生成 MUMmer 测试合成数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
