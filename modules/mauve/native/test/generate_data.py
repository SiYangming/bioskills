#!/usr/bin/env python3
"""生成 Mauve native 测试用的合成输入。

progressiveMauve 比对需要真实基因组才能产出有意义结果，合成数据无法覆盖真实计算，
因此本脚本生成「结构合法的迷你 FASTA + 最小 XMFA」，供 run_test.sh 做 argv 构造断言；
若本机已安装 progressiveMauve，还会用迷你基因组跑一次真实冒烟。

产出：
  <outdir>/genome1.fasta / genome2.fasta / genome3.fasta   输入基因组（FASTA）
  <outdir>/alignment.xmfa                                  最小 XMFA（gui / apply_backbone 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    for i in (1, 2, 3):
        (outdir / f"genome{i}.fasta").write_text(
            f">genome{i}\n{SEQ}{SEQ}\n", encoding="utf-8"
        )
    # 最小合法 XMFA：一个 LCB（两条序列块），块间以 '=' 分隔
    (outdir / "alignment.xmfa").write_text(
        "> 1:1-128 + genome1\n"
        f"{SEQ}{SEQ}\n"
        "> 2:1-128 + genome2\n"
        f"{SEQ}{SEQ}\n"
        "=\n",
        encoding="utf-8",
    )
    print(f"已生成 Mauve 测试合成数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
