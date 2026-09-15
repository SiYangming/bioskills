#!/usr/bin/env python3
"""生成 signalp native 测试用的合成输入。

SignalP 5.0 需要真实蛋白质序列 + 授权模型才能预测，合成数据无法覆盖真实计算；
本脚本生成「最小蛋白质 FASTA + 说明」，run_test.sh 在 signalp 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/proteins.fasta   最小蛋白质 FASTA（含一段典型分泌蛋白信号肽序列）
"""
from __future__ import annotations

import sys
from pathlib import Path

# 一段典型真核分泌蛋白（含 N 端信号肽样疏水段），仅作 argv/流程占位
PROTEINS = [
    ("sp_demo_1", "MKWVTFISLLFSSAYSRGVFRR"),          # albumin 样信号肽
    ("sp_demo_2", "MGWSCIILFLVATATGVHSQ"),            # 免疫球蛋白重链信号肽
    ("no_sp_demo", "MPEPTIDEKELSEQUENCEWITHOUTSIGNAL"),
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    lines: list[str] = [
        "# PLACEHOLDER: SignalP 5.0 需授权模型 + 真实蛋白序列才能预测\n",
        "# 合成数据仅用于 argv 构造验证（见 run_test.sh）\n",
    ]
    for name, seq in PROTEINS:
        lines.append(f">{name}\n")
        lines.append(f"{seq}\n")
    (outdir / "proteins.fasta").write_text("".join(lines), encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}/proteins.fasta")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
