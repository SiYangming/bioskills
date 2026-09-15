#!/usr/bin/env python3
"""生成 pilon native 测试用的合成输入。

pilon correct 需要真实比对 BAM（已排序+索引）与参考组装才能做真实修正，合成数据无法覆盖真实
计算。因此本脚本生成「可构造 argv 的占位输入 + 说明」，run_test.sh 在 pilon 未安装时退化为
「--list-commands/--schema 自省 + python 层 argv 构造断言（monkeypatch _resolve_binary/_resolve_jar）」。

产出：
  <outdir>/genome.fasta     最小参考组装（2 条 contig）
  <outdir>/frags.sorted.bam 文本占位（paired-end 比对输入）
  <outdir>/unpaired.bam     文本占位（未配对比对输入）
  <outdir>/tracks.txt       最小 tracks 文件
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
        ">contig1\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
        ">contig2\n"
        "TTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n",
        encoding="utf-8",
    )
    (outdir / "frags.sorted.bam").write_text(
        "# PLACEHOLDER: pilon correct 需要真实 sorted+indexed BAM（bowtie2 -S ... | samtools sort）\n",
        encoding="utf-8",
    )
    (outdir / "unpaired.bam").write_text(
        "# PLACEHOLDER: pilon --unpaired 需要真实 sorted+indexed BAM\n", encoding="utf-8"
    )
    (outdir / "tracks.txt").write_text(
        "# PLACEHOLDER: pilon tracks 文件（每行区域）\n"
        "contig1\t1\t80\n",
        encoding="utf-8",
    )
    print(f"已生成 pilon 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
