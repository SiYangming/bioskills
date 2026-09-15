#!/usr/bin/env python3
"""生成 finishersc native 测试用的合成输入。

FinisherSC 主流程需要真实长读与组装（并跑 MUMmer）才能产出 improved3.fasta，合成数据无法覆盖真实
计算。因此本脚本生成「可构造 argv 的占位输入」，run_test.sh 在 finisherSC.py 未部署时退化为
「--list-commands/--schema 自省 + python 层 argv 构造断言（monkeypatch _resolve_binary）」。

产出：
  <outdir>/work/contigs.fasta   最小 contig 集（占位）
  <outdir>/work/raw_reads.fasta 最小长读集（占位）
  <outdir>/mummer/bin/nucmer    占位（MUMmer 目录形状）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    work = outdir / "work"
    mbin = outdir / "mummer" / "bin"
    work.mkdir(parents=True, exist_ok=True)
    mbin.mkdir(parents=True, exist_ok=True)

    # 最小 contig 集（两条，中间含 N gap）
    (work / "contigs.fasta").write_text(
        ">tig00000001\n"
        "ACGTACGTACGTACGTACGTNNNNNNNNNNACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
        ">tig00000002\n"
        "TTTTGGGGCCCCAAAANNNNNNTTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n",
        encoding="utf-8",
    )
    # 最小长读集（两条，覆盖上面两个 contig 的区段）
    (work / "raw_reads.fasta").write_text(
        ">read1\n"
        "ACGTACGTACGTACGTACGTGGGGACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC\n"
        ">read2\n"
        "TTTTGGGGCCCCAAAACCCCTTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATT\n",
        encoding="utf-8",
    )
    # MUMmer 目录形状占位（nucmer / show-coords 由真实 MUMmer 提供）
    for tool in ("nucmer", "show-coords", "delta-filter", "mummer"):
        (mbin / tool).write_text(f"# PLACEHOLDER: 真实 MUMmer {tool} 二进制\n", encoding="utf-8")
        (mbin / tool).chmod(0o755)
    print(f"已生成 finishersc 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
