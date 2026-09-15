#!/usr/bin/env python3
"""生成 tracer native 测试用的合成输入。

Tracer 为交互式 Java GUI，读取 MCMC trace/日志文件（Tab 分隔，首行列名，
首列为 state/generation，其后为连续参数列）。本脚本生成一个最小 BEAST 风格
日志与第二个日志，供 run_test.sh 做 argv 构造验证（GUI 不产出文件）。

产出：
  <outdir>/beast.log      最小 MCMC trace 日志（BEAST 风格表头）
  <outdir>/beast2.log     第二个日志（多文件载入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def _trace_log(n: int) -> str:
    header = "state\tposterior\tlikelihood\tprior\ttreeLength\trate\n"
    rows = []
    for i in range(n):
        state = i * 1000
        rows.append(
            f"{state}\t{-1200 + i * 0.5:.3f}\t{-1250 + i * 0.4:.3f}\t"
            f"{50 + i * 0.1:.3f}\t{0.6 + i * 0.001:.4f}\t{0.9 + i * 0.002:.4f}"
        )
    return header + "\n".join(rows) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "beast.log").write_text(_trace_log(50), encoding="utf-8")
    (outdir / "beast2.log").write_text(_trace_log(50), encoding="utf-8")
    print(f"已生成测试数据（MCMC trace 日志） -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
