#!/usr/bin/env python3
"""生成 hmmer（HMMER 3.x）native 测试用的合成数据。

产出（<outdir> 下）：
  family.sto   5 条等长蛋白序列的 Stockholm 多序列比对（hmmbuild 输入）
  proteins.fa  蛋白序列库 FASTA（含与 family 同源的 hit 与无关 decoy；hmmsearch 输入）

说明：序列为合成 motif（非真实蛋白家族），仅用于跑通 hmmbuild→hmmpress→hmmsearch 链路。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 40 aa 的合成共识序列（20 种氨基酸循环两遍）
CONSENSUS = "ACDEFGHIKLMNPQRSTVWY" * 2

# family.sto 的成员：在共识上做少量取代，保持等长（已对齐）
VARIANTS = [
    ("seq1", []),
    ("seq2", [(3, "K"), (17, "E")]),
    ("seq3", [(8, "A"), (25, "G")]),
    ("seq4", [(12, "L"), (30, "V")]),
    ("seq5", [(2, "R"), (21, "T")]),
]

# proteins.fa：一条近同源 hit + 两条无关 decoy
HIT_SEQ = CONSENSUS
HIT2_SEQ = "".join("W" if i % 7 == 0 else c for i, c in enumerate(CONSENSUS))
DECOY_SEQ = "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ"  # 与 family 无关的合成序列


def _substitute(seq: str, subs) -> str:
    chars = list(seq)
    for pos, aa in subs:
        chars[pos] = aa
    return "".join(chars)


def write_stockholm(path: Path) -> None:
    with open(path, "w") as fh:
        fh.write("# STOCKHOLM 1.0\n")
        fh.write("#=GF ID teach_family\n")
        fh.write("#=GF DE synthetic protein family for hmmer native test\n")
        width = max(len(name) for name, _ in VARIANTS)
        for name, subs in VARIANTS:
            fh.write(f"{name.ljust(width)}  {_substitute(CONSENSUS, subs)}\n")
        fh.write("//\n")


def write_fasta(path: Path) -> None:
    seqs = {"hit_exact": HIT_SEQ, "hit_variant": HIT2_SEQ, "decoy": DECOY_SEQ}
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_stockholm(outdir / "family.sto")
    write_fasta(outdir / "proteins.fa")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
