#!/usr/bin/env python3
"""生成 canu native 测试用的合成输入。

canu 完整组装需要真实 PacBio/Nanopore 长读数据（纠错 + 组装耗时极长），合成数据无法覆盖真实计算。
因此本脚本生成「可解析的小型长读 FASTA（占位）+ 说明」，run_test.sh 在 canu 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/subreads.fasta   合成长读序列（数条，仅用于 argv 构造验证）
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

    seq = "ACGT" * 250  # 1000 bp 占位长读
    with open(outdir / "subreads.fasta", "w", encoding="utf-8") as fh:
        for i in range(1, 4):
            fh.write(f">read_{i}\n{seq}\n")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
