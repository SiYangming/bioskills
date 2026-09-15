#!/usr/bin/env python3
"""生成 snoscan native 测试用的合成输入。

snoscan 需要真实的 rRNA 序列与基因组序列才能产生有意义的候选；合成数据只用于
run_test.sh 做「argv 构造验证」与「可解析输入冒烟」，不覆盖真实预测计算。

产出：
  <outdir>/rRNA.fa        最小靶 rRNA（含一个甲基化位点附近序列）
  <outdir>/query.fa       最小待查序列（FASTA）
  <outdir>/meth.sites     已知甲基化位点文件（占位）
  <outdir>/hits.txt       sort-snos 的输入（占位命中文件）
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

    (outdir / "rRNA.fa").write_text(
        ">Sc-rRNA test\n"
        "GGCCAUAUCGGAUGGUCAGUCCUAGCGAAACCUGGAAUGGAUCAGAUAUCGUCGGUUC\n",
        encoding="utf-8",
    )
    (outdir / "query.fa").write_text(
        ">query1\n"
        "AUGGAUCAGAUAUCGUCGGUUCGAUCGAUCGAUCGAUCGAUCGAUCGAUCGAUCGAUCG\n",
        encoding="utf-8",
    )
    (outdir / "meth.sites").write_text(
        "# methylation sites (placeholder; see lowelab Sc-meth.sites format)\n"
        "Am1234\n",
        encoding="utf-8",
    )
    (outdir / "hits.txt").write_text(
        ">> query1 100 (10-40) Cmpl: Sc-rRNA-Am1234 (guide)\n",
        encoding="utf-8",
    )
    print(f"已生成 snoscan 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
