#!/usr/bin/env python3
"""生成 edena native 测试用的合成输入。

Edena 组装需要真实测序 reads，合成数据无法覆盖真实计算；本脚本生成「文本占位」
FASTQ，供 run_test.sh 做 argv 构造断言（不真实执行 edena）。

产出：
  <outdir>/fragment.1.fastq   PE read1 占位
  <outdir>/fragment.2.fastq   PE read2 占位
  <outdir>/se.fastq           SE read 占位
"""
from __future__ import annotations

import sys
from pathlib import Path


def _fastq(path: Path, n: int) -> None:
    lines = []
    for i in range(1, n + 1):
        lines += [f"@read{i}", "ACGTACGTACGTACGT", "+", "IIIIIIIIIIIIIIII"]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    _fastq(outdir / "fragment.1.fastq", 2)
    _fastq(outdir / "fragment.2.fastq", 2)
    _fastq(outdir / "se.fastq", 2)
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
