#!/usr/bin/env python3
"""生成 viennarna native 测试用的合成输入。

RNAfold 是真实可运行的（输入 RNA 序列 → MFE 结构 + 自由能），故本脚本生成可折叠的
最小 pre-miRNA 样序列；run_test.sh 除 argv 构造验证外，若本机装了 RNAfold 还会跑真实折叠回归。

产出：
  <outdir>/pre_mirna.fa       最小 RNA 序列（pre-miRNA 样，可折叠出发夹）
  <outdir>/structure.txt      序列 + 点括号结构（供 RNAeval 评估自由能）
"""
from __future__ import annotations

import sys
from pathlib import Path

_SEQ = "UGAGGUAGUAGGUUGUAUAGUUCUACCAGUAGGUUGUAUAGUUACUGUAGGUUGUAUAGUUCA"  # 发夹样序列
# 结构串长度必须与序列一致（前 15 配对 / 中段环 / 后 15 配对），仅供 RNAeval 冒烟
_STRUCTURE = "(" * 15 + "." * (len(_SEQ) - 30) + ")" * 15


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "pre_mirna.fa").write_text(f">pre_mirna_test\n{_SEQ}\n", encoding="utf-8")
    (outdir / "structure.txt").write_text(f">pre_mirna_test\n{_SEQ}\n{_STRUCTURE}\n", encoding="utf-8")
    print(f"已生成 viennarna 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
