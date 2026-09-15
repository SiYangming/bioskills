#!/usr/bin/env python3
"""生成 fasta native 测试用的合成输入。

FASTA（fasta36 系列）的搜索程序需要真实序列库才能覆盖真实计算；本脚本生成最小序列，run_test.sh
以 python 构造 argv 验证命令构建（monkeypatch 二进制路径）为主；若本机已安装 FASTA，
再额外做一次真实搜索冒烟。

产出：
  <outdir>/query.fasta   2 条查询序列
  <outdir>/db.fasta      3 条目标库序列
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

    (outdir / "query.fasta").write_text(
        ">query1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">query2\nGAVLIPFYWSTCMNQDEKRH\n",
        encoding="utf-8",
    )
    (outdir / "db.fasta").write_text(
        ">db1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQANQEL\n"
        ">db2\nGAVLIPFYWSTCMNQDEKRHACDEFGHIKLMNPQRSTVWY\n"
        ">db3\nAAAAAAAAGGGGGGGGCCCCCCCC\n",
        encoding="utf-8",
    )
    print(f"已生成测试序列 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
