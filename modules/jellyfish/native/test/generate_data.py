#!/usr/bin/env python3
"""生成 jellyfish native 测试用的合成输入。

jellyfish count 需要真实序列才能产出 .jf；合成数据无法覆盖真实计数。
因此本脚本生成「迷你 FASTQ + 文本占位」，run_test.sh 在 jellyfish 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/reads_1.fastq    迷你 FASTQ（count 输入）
  <outdir>/reads_2.fastq    迷你 FASTQ（count 输入，PE）
  <outdir>/mer_counts.jf    .jf 计数文件文本占位（histo/stats/query/dump 输入）
  <outdir>/mer_counts.histo 两列 k-mer 频率直方图（count / species number）
"""
from __future__ import annotations

import sys
from pathlib import Path

_R1 = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"
_R2 = "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCAT"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1]).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    for name, seq in (("reads_1.fastq", _R1), ("reads_2.fastq", _R2)):
        (outdir / name).write_text(
            f"@read1\n{seq}\n+\n{'I' * len(seq)}\n"
            f"@read2\n{seq[::-1]}\n+\n{'I' * len(seq)}\n",
            encoding="utf-8",
        )

    (outdir / "mer_counts.jf").write_text(
        "# PLACEHOLDER: jellyfish count 产出的 .jf 二进制计数文件\n", encoding="utf-8"
    )
    rows = [f"{d}\t{v}" for d, v in
            [(1, 180000), (2, 40000), (3, 12000), (4, 8000),
             (5, 6200), (6, 4100), (7, 2600), (8, 1500)]]
    (outdir / "mer_counts.histo").write_text("\n".join(rows) + "\n", encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
