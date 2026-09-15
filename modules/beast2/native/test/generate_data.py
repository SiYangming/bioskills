#!/usr/bin/env python3
"""生成 beast2 native 测试用的合成输入。

BEAST2 的 beast 真实运行需要完整 XML（BEAUti 生成）与真实比对，MCMC 耗时较长；
本脚本生成「可解析的最小占位输入」，run_test.sh 用其文件路径验证命令构造（argv）。

产出：
  <outdir>/input.xml     最小 BEAST 输入占位（beast）
  <outdir>/input.trees   posterior tree 采样占位（treeannotator / densitetree）
  <outdir>/a.log / b.log MCMC log 占位（logcombiner / loganalyser）
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

    (outdir / "input.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!-- PLACEHOLDER: BEAST2 输入 XML（真实文件由 BEAUti 生成） -->\n"
        "<beast version='2.5'>\n  <run id='mcmc' chainLength='1000'>\n  </run>\n</beast>\n",
        encoding="utf-8",
    )
    (outdir / "input.trees").write_text(
        "#NEXUS\nbegin trees;\n"
        "tree STATE_0 = [&R] ((sp1:0.1,sp2:0.1):0.1,(sp3:0.1,sp4:0.1):0.1);\n"
        "tree STATE_1000 = [&R] ((sp1:0.12,sp2:0.09):0.11,(sp3:0.1,sp4:0.12):0.09);\n"
        "end;\n",
        encoding="utf-8",
    )
    for name in ("a.log", "b.log"):
        (outdir / name).write_text(
            "state\tposterior\tlikelihood\tprior\n0\t-100.0\t-110.0\t10.0\n"
            "1000\t-99.5\t-109.8\t10.3\n",
            encoding="utf-8",
        )
    print(f"已生成 beast2 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
