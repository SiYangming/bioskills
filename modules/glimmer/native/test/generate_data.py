#!/usr/bin/env python3
"""生成 Glimmer3（glimmer）native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fna   一个小型「基因样」原核基因组：若干条长编码 ORF（ATG 起始、以 TAA/TAG/TGA 终止，
               长度 ≥ 600 bp）+ 短间隔区，供 long-orfs 挑选训练 ORF 走通教学链路。

说明：ORF 用固定随机种子、按密码子表随机拼接（不含框内终止密码子），长度足够长，
便于 long-orfs 在熵距离阈值内挑出训练 ORF；不同机器/重复运行结果可复现。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

# 20 种氨基酸对应密码子（不含终止密码子 TAA/TAG/TGA）
SENSE_CODONS = [
    # F  L  I  M  V  S  P  T  A  Y  H  Q  N  K  D  E  C  W  R  G
    "TTT", "TTC", "TTA", "TTG", "CTT", "CTC", "CTA", "CTG",
    "ATT", "ATC", "ATA", "ATG",
    "GTT", "GTC", "GTA", "GTG",
    "TCT", "TCC", "TCA", "TCG", "AGT", "AGC",
    "CCT", "CCC", "CCA", "CCG",
    "ACT", "ACC", "ACA", "ACG",
    "GCT", "GCC", "GCA", "GCG",
    "TAT", "TAC", "CAT", "CAC", "CAA", "CAG", "AAT", "AAC",
    "AAA", "AAG", "GAT", "GAC", "GAA", "GAG",
    "TGT", "TGC", "TGG",
    "CGT", "CGC", "CGA", "CGG", "AGA", "AGG",
    "GGT", "GGC", "GGA", "GGG",
]
STOPS = ["TAA", "TAG", "TGA"]

N_GENES = 6            # ORF 数量
GENE_LEN = 720         # 每个 ORF 长度（bp，3 的倍数；不含终止密码子）
SPACER_MIN, SPACER_MAX = 36, 72


def make_gene(rng: random.Random) -> str:
    n_codons = GENE_LEN // 3
    codons = ["ATG"] + [rng.choice(SENSE_CODONS) for _ in range(n_codons - 1)]
    return "".join(codons) + rng.choice(STOPS)


def make_spacer(rng: random.Random) -> str:
    n = rng.randint(SPACER_MIN, SPACER_MAX)
    return "".join(rng.choice("ACGT") for _ in range(n))


def wrap(seq: str, width: int = 70) -> str:
    return "\n".join(seq[i:i + width] for i in range(0, len(seq), width))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(20260910)
    seq = make_spacer(rng) + "".join(make_gene(rng) + make_spacer(rng) for _ in range(N_GENES))
    with open(outdir / "genome.fna", "w") as fh:
        fh.write(">synthetic_genome\n")
        fh.write(wrap(seq) + "\n")
    print(f"已生成测试数据 -> {outdir}/genome.fna（{len(seq)} bp，{N_GENES} 个长 ORF）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
