#!/usr/bin/env python3
"""生成 isolasso native 测试用的合成输入。

IsoLasso 真实组装需 SAM/BAM 比对 + 二次规划求解，合成数据无法覆盖真实计算。
因此本脚本生成「结构合法的最小文本输入」，run_test.sh 在 isolasso 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/alignments.sam   最小 SAM（含 @HD/@SQ 头 + 少量比对）
  <outdir>/sample.instance  instance 文件占位（isolasso 子命令输入）
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

    sam_header = "@HD\tVN:1.0\tSO:coordinate\n@SQ\tSN:chr1\tLN:1000\n"
    read = "A" * 50
    qual = "I" * 50
    rows = [f"r{i}\t0\tchr1\t{1 + i * 5}\t60\t50M\t*\t0\t0\t{read}\t{qual}" for i in range(4)]
    (outdir / "alignments.sam").write_text(sam_header + "\n".join(rows) + "\n", encoding="utf-8")

    # instance 文件占位（isolasso 二次规划输入，真实格式由 processsam 生成）
    (outdir / "sample.instance").write_text(
        "# PLACEHOLDER: IsoLasso .instance（真实文件由 processsam 生成；此处仅供 argv 构造测试）\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
