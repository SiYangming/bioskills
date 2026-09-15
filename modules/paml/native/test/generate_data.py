#!/usr/bin/env python3
"""生成 paml native 测试用的合成输入。

PAML 各程序读取控制文件（.ctl）；真实分析需要真实的多序列比对与树。
本脚本生成「可解析的最小 .ctl + 最小 Phylip 比对 + 最小 Newick 树」，
run_test.sh 用它们验证命令构造（argv）与 --list-commands / --schema 自省。

产出：
  <outdir>/input.phy          最小 Phylip 比对（4 序列 x 12 位点）
  <outdir>/input.trees        最小 Newick 树（含 PAML 头部 "4 1"）
  <outdir>/baseml.ctl         baseml 控制文件
  <outdir>/codeml.ctl         codeml 控制文件
  <outdir>/yn00.ctl           yn00 控制文件
  <outdir>/mcmctree.ctl       mcmctree 控制文件
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

    # 最小 Phylip 比对（严格格式：名称 10 列 + 序列；PAML 会自行读取）
    (outdir / "input.phy").write_text(
        "  4   12\n"
        "sp1  ATGAAACCCGGG\n"
        "sp2  ATGAAACCCGGA\n"
        "sp3  ATGAAACCGGGG\n"
        "sp4  ATGAAACCTGGG\n",
        encoding="utf-8",
    )
    # 最小 Newick 树（PAML 树文件首行 = 物种数 树数）
    (outdir / "input.trees").write_text("4 1\n((sp1,sp2),(sp3,sp4));\n", encoding="utf-8")

    (outdir / "baseml.ctl").write_text(
        "seqfile = input.phy\ntreefile = input.trees\noutfile = mlb\n", encoding="utf-8"
    )
    (outdir / "codeml.ctl").write_text(
        "seqfile = input.phy\ntreefile = input.trees\noutfile = mlc\n", encoding="utf-8"
    )
    (outdir / "yn00.ctl").write_text(
        "seqfile = input.phy\noutfile = yn\n", encoding="utf-8"
    )
    (outdir / "mcmctree.ctl").write_text(
        "seqfile = input.phy\ntreefile = input.trees\noutfile = mcmc.out\n",
        encoding="utf-8",
    )
    print(f"已生成 paml 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
