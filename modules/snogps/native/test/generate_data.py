#!/usr/bin/env python3
"""生成 snogps native 测试用的合成输入。

snoGPS 需要真实基因组序列 + descriptor/target/scoretable 才能产出有意义的候选；
合成数据只用于 run_test.sh 做「argv 构造验证」与「可解析输入冒烟」，不覆盖真实预测计算。

产出：
  <outdir>/sequence.fa      最小待查序列（FASTA）
  <outdir>/descriptor.desc  descriptor 文件（占位；真实文件见源码 desc/ 目录）
  <outdir>/target.targ      target 文件（占位；真实文件见源码 targs/ 目录）
  <outdir>/hits.txt         sortHits.pl 的输入（占位命中文件）
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

    (outdir / "sequence.fa").write_text(
        ">chr_test\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "descriptor.desc").write_text(
        "# snoGPS descriptor placeholder (see upstream desc/ directory)\n"
        "stem 2\n"
        "hairpin 2\n",
        encoding="utf-8",
    )
    (outdir / "target.targ").write_text(
        "# snoGPS target placeholder (see upstream targs/ directory)\n"
        ">target1\n"
        "NNNNUNNNN\n",
        encoding="utf-8",
    )
    (outdir / "hits.txt").write_text(
        ">chr_test_1 5.0 (100-140) target1\n",
        encoding="utf-8",
    )
    print(f"已生成 snogps 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
