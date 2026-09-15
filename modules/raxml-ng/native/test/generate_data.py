#!/usr/bin/env python3
"""生成 raxml-ng native 测试用的合成输入。

RAxML-NG 输入为多序列比对（FASTA/Phylip）；evaluate 模式还需一棵 Newick 树。本脚本生成一份小规模
核酸比对与一棵 4 叶树，供 run_test.sh 做参数构造验证；若本机装了 raxml-ng，只做 `--parse`（快速）冒烟。

⚠️ 注意：4 条序列必须**互不相同**——RAxML-NG 会去重完全相同的序列，若全部相同则去重后仅剩 1 条，
`--parse` 会以 "Stepwise parsimony requires at least three tips" 失败（本机实测）。故各序列在共识
序列上引入若干取代。

产出：
  <outdir>/sample.fa     4 条等长（57 bp）且互不相同的核酸比对（FASTA）
  <outdir>/sample.nwk    4 叶 Newick 树（evaluate 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

# 57 bp 共识序列（19 个密码子）
CONSENSUS = "ATGAAAACCGCCTATATTGCCAAACAGCGCCAGATTTCTTTTGTGAAAAGTCATGGT"

# 各序列在共识序列上的取代（0-based 位置 → 碱基），保证 4 条序列两两不同
VARIANTS = {
    "sp1": [],
    "sp2": [(4, "G"), (25, "G"), (40, "C")],
    "sp3": [(12, "A"), (33, "G"), (50, "A")],
    "sp4": [(7, "T"), (20, "T"), (45, "G")],
}


def _substitute(seq: str, subs) -> str:
    chars = list(seq)
    for pos, base in subs:
        chars[pos] = base
    return "".join(chars)


def build_seqs() -> dict[str, str]:
    seqs = {name: _substitute(CONSENSUS, subs) for name, subs in VARIANTS.items()}
    # 断言：长度一致且两两不同（否则 raxml-ng --parse 会因去重后不足 3 条而报错）
    assert len(set(seqs.values())) == len(seqs), "测试序列必须互不相同"
    assert len({len(s) for s in seqs.values()}) == 1, "测试序列必须等长"
    return seqs


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with (outdir / "sample.fa").open("w", encoding="utf-8") as fh:
        for name, seq in build_seqs().items():
            fh.write(f">{name}\n{seq}\n")

    (outdir / "sample.nwk").write_text("((sp1,sp2),(sp3,sp4));\n", encoding="utf-8")

    print(f"已生成测试输入 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
