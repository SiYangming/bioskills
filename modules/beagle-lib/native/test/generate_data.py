#!/usr/bin/env python3
"""生成 beagle-lib native 测试用的合成输入。

BEAGLE 是库（libhmsbeagle），真实编译安装需 autotools 与完整源码；
本脚本生成「可解析的最小源码目录占位」，run_test.sh 用其路径验证命令构造（argv）。

产出：
  <outdir>/beagle-lib-3.1.2/autogen.sh     源码目录占位（含可执行 autogen.sh）
  <outdir>/beagle-lib-3.1.2/configure.ac   源码目录占位（configure.ac）
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    srcdir = outdir / "beagle-lib-3.1.2"
    srcdir.mkdir(parents=True, exist_ok=True)

    autogen = srcdir / "autogen.sh"
    autogen.write_text("#!/bin/sh\n# PLACEHOLDER: 真实 autogen.sh 由官方源码提供\n", encoding="utf-8")
    os.chmod(autogen, 0o755)
    (srcdir / "configure.ac").write_text(
        "AC_INIT([libhmsbeagle], [3.1.2])\nAC_CONFIG_FILES([hmsbeagle-1.pc])\nAC_OUTPUT\n",
        encoding="utf-8",
    )
    print(f"已生成 beagle-lib 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
