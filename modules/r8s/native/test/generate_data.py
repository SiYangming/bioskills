#!/usr/bin/env python3
"""生成 r8s native 测试用的合成输入。

r8s 以 NEXUS 文件（trees 块 + r8s 块）为输入，真实分析需要真实树与化石校准。
本脚本生成「可解析的最小 NEXUS 输入」，run_test.sh 用其文件路径验证命令构造（argv）。

产出：
  <outdir>/r8s_in.txt   最小 NEXUS 输入（trees 块 + r8s 块的 fixage/divtime 指令）
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

    (outdir / "r8s_in.txt").write_text(
        "#NEXUS\n"
        "begin trees;\n"
        "tree tree_1 = [&R] (((sp1:0.1,sp2:0.1):0.1,(sp3:0.1,sp4:0.1):0.1):0.05);\n"
        "end;\n"
        "begin r8s;\n"
        "blformat lengths=persite nsites=100 ulrametric=no;\n"
        "fixage taxon=sp1 age=89;\n"
        "divtime method=PL algorithm=TN;\n"
        "showage;\n"
        "describe plot=chrono_description;\n"
        "end;\n",
        encoding="utf-8",
    )
    print(f"已生成 r8s 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
