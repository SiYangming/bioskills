#!/usr/bin/env python3
"""生成 tmhmm native 测试用的合成输入。

TMHMM 2.0c 需授权模型才能预测，合成数据无法覆盖真实计算；本脚本生成「最小蛋白质
FASTA + 说明」，run_test.sh 在 tmhmm 未安装时退化为「用 python 构造 argv 验证命令构建
不崩溃 + 用 stub 二进制验证 stdout→-o 重定向」。

产出：
  <outdir>/proteins_mature.fasta   最小蛋白质 FASTA（SignalP 导出成熟序列的占位）
"""
from __future__ import annotations

import sys
from pathlib import Path

PROTEINS = [
    ("mature_demo_1", "MKWVTFISLLFSSAYSRGVFRR"),
    ("mature_demo_2", "MGWSCIILFLVATATGVHSQ"),
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    lines: list[str] = ["# PLACEHOLDER: TMHMM 2.0c 需授权模型 + 真实蛋白序列才能预测\n"]
    for name, seq in PROTEINS:
        lines.append(f">{name}\n")
        lines.append(f"{seq}\n")
    (outdir / "proteins_mature.fasta").write_text("".join(lines), encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}/proteins_mature.fasta")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
