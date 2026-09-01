#!/usr/bin/env python3
"""生成 dorado native 测试用的合成输入。

dorado basecaller 需要真实 POD5/FAST5 原始信号，合成数据无法覆盖真实计算。
因此本脚本生成「文本占位 + 说明」，run_test.sh 在 dorado 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」，不执行真实 dorado。

产出：
  <outdir>/pod5/reads.pod5   文本占位（basecall 输入目录）
  <outdir>/reads.fastq       最小 FASTQ 占位（demux 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    pod5_dir = outdir / "pod5"
    pod5_dir.mkdir(parents=True, exist_ok=True)

    (pod5_dir / "reads.pod5").write_text(
        "# PLACEHOLDER: dorado basecaller 需要真实 POD5/FAST5 原始信号\n", encoding="utf-8"
    )
    (outdir / "reads.fastq").write_text(
        "@read1\nACGTACGTACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIII\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
