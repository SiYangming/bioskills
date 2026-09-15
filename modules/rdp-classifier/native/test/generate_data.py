#!/usr/bin/env python3
"""生成 rdp-classifier native 测试用的合成输入。

RDP Classifier 需要真实 16S rRNA 序列 + 训练集才能产出分类结果，合成数据无法覆盖
真实分类计算，因此本脚本生成「最小 FASTA + 训练集占位」，run_test.sh 在
rdp_classifier 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/rep_set.fna                  最小 16S-like 查询序列（3 条）
  <outdir>/rRNAClassifier.properties    训练集属性文件占位（-t 参数输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

# 3 条最小查询序列（仅用于 argv 构造与占位；真实分类需完整 16S 序列）
_SEQS = [
    ("seq1", "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAACGGTAA"),
    ("seq2", "AGAGTTTGATCMTGGCTCAGATTGAACGCTGGCGGCATGCCTAACACATGCAAGTCGAACGGTAA"),
    ("seq3", "GACGAACGCTGGCGGCGTGCCTAACACATGCAAGTCGAACGAGAAAGCCCTTCGGGGTGAGTAA"),
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with open(outdir / "rep_set.fna", "w", encoding="utf-8") as fh:
        for name, seq in _SEQS:
            fh.write(f">{name}\n{seq}\n")

    (outdir / "rRNAClassifier.properties").write_text(
        "# PLACEHOLDER: RDP Classifier 训练集属性文件（真实文件由 -t 提供或使用内置默认训练集）\n"
        "trainPropFile=builtin-16s\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
