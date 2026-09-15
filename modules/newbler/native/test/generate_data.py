#!/usr/bin/env python3
"""生成 newbler native 测试用的合成输入。

Newbler 真正组装需要真实 454 SFF reads，且软件已淘汰（官网停服、无安装渠道），
本脚本只生成「文本占位 SFF + 迷你参考 FASTA」，run_test.sh 采用「python 构造 argv
验证命令构建不崩溃」的断言方式（不执行真实组装）。

产出：
  <outdir>/454Reads.sff    454 reads 文本占位（runAssembly/runMapping 输入）
  <outdir>/reference.fasta 迷你参考序列（runMapping 的参考输入）
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

    (outdir / "454Reads.sff").write_text(
        "# PLACEHOLDER: Newbler runAssembly/runMapping 需要真实 454 SFF reads\n",
        encoding="utf-8",
    )
    (outdir / "reference.fasta").write_text(
        ">ref1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
