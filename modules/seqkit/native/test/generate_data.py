#!/usr/bin/env python3
"""生成 seqkit native 测试用的合成输入。

seqkit 是 FASTA/Q 处理工具集，真实计算依赖 seqkit 二进制；合成数据无法在本机无 seqkit 时覆盖
真实计算。因此本脚本生成可直接被 seqkit 读取的最小 FASTA / FASTQ 样本，run_test.sh 在 seqkit
未安装时退化为「用 python 构造 argv 验证命令构建不崩溃 + parser 断言」；seqkit 已安装时
（conda activate seqkit-native / PATH 有 seqkit）额外做真实冒烟。

产出：
  <outdir>/test.fa    最小 FASTA（5 条：含重复序列、大小写混合，供 rmdup/sort/grep/sample/translate）
  <outdir>/test.fq    最小 FASTQ（3 条，供 stats/fq2fa）
  <outdir>/ids.txt    ID 列表（供 grep -f）
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

    # FASTA：5 条（seq3 与 seq1 序列重复——rmdup -s 时应去掉一条；gene001 供 grep -p）
    (outdir / "test.fa").write_text(
        ">seq1 duplicated seq\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGT\n"          # 32 bp
        ">gene001\n"
        "ATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAG\n"     # 40 bp CDS（可翻译）
        ">seq3\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGT\n"          # 与 seq1 序列相同
        ">seq10\n"
        "GGGGCCCCAAAATTTT\n"                           # 16 bp
        ">seq2\n"
        "aCgTtGgCcAaTt\n"                             # 14 bp 小写混合（ignore-case 用）
        "", encoding="utf-8",
    )
    # FASTQ：3 条（Phred+33；序列与质量串严格等长）
    (outdir / "test.fq").write_text(
        "@read1 comment\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGT\n"          # 32 bp
        "+\n"
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"          # 32
        "@read2\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"  # 40 bp
        "+\n"
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"  # 40
        "@read3\n"
        "TTTTCCCCAAAAGGGG\n"                          # 16 bp
        "+\n"
        "IIIIIIIIIIIIIIII\n",                         # 16
        encoding="utf-8",
    )
    (outdir / "ids.txt").write_text(
        f"seq1\ngene001\n", encoding="utf-8"
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
