#!/usr/bin/env python3
"""生成 trnascan-se native 测试用的合成小基因组。

产出（<outdir> 下）：
  genome.fa  合成小基因组（2 条 contig，总长 ~1.3 kb）：
             - scerevisiae_trna_region：随机「类基因」骨架中嵌入一条全长经典
               S. cerevisiae（酿酒酵母）tRNA-Phe（GAA 反密码子，76 nt，DNA 化），
               用于真核默认模式的真实回归（装有 tRNAscan-SE 时，默认真核模型应能检出）；
             - random_negative：纯随机 GC≈40% 骨架（无刻意嵌入 tRNA 的阴性对照）。

说明：
- 动态生成、体积 <3KB；仅用于 run_test.sh 的参数/自省回归，及装有 tRNAscan-SE 的
  机器上用真核默认模式做真实检测自测（conda 包内自带 covariance model，无需另配）。
- 序列固定（seed=20260909），可重复断言。嵌入序列为公认经典酵母 tRNA-Phe 全长
  （Sprinzl 编译 / 经典 RNA 结构教材通用序列，教学演示常用）；DNA 化（T 替 U）。
- 原核（-B）教学/回归请用真实 E. coli 基因组序列文件（如 NCBI NC_000913.3），
  本文件不生成 E. coli 序列（避免以真核 tRNA 冒充原核数据误导教学）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 20260909

# 经典 S. cerevisiae tRNA-Phe（GAA 反密码子）全长 76 nt，DNA 化。
# 公认序列（RNA 版）：GCGGAUUUAGCUCAGUUGGGAGAGCGCCAGACUGAAGAUCUGGAGGUCCUGUGUUCGAUCCACAGAAUUCGCACCA
YEAST_TRNA_PHE = (
    "GCGGATTTAGCTCAGTTGGGAGAGCGCCAGACTGAAGATCTGGAGGT"
    "CCTGTGTTCGATCCACAGAATTCGCACCA"
)


def rand_seq(rng: random.Random, length: int, gc: float = 0.40) -> str:
    """生成伪随机 DNA 片段（gc 为 GC 比例）。"""
    pool = "GC" * int(round(gc * 10)) + "AT" * int(round((1 - gc) * 10))
    return "".join(rng.choice(pool) for _ in range(length))


def write_fasta(path: Path, records: list[tuple[str, str]]) -> None:
    with open(path, "w") as fh:
        for name, seq in records:
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    # 嵌入序列自检：经典酵母 tRNA-Phe 应恰为 76 nt（非 76 说明复制有误，立即暴露）
    assert len(YEAST_TRNA_PHE) == 76, f"酵母 tRNA-Phe 长度异常: {len(YEAST_TRNA_PHE)}"
    assert set(YEAST_TRNA_PHE) <= set("ACGT")

    rng = random.Random(_SEED)
    left = rand_seq(rng, 220)
    right = rand_seq(rng, 220)
    contig1 = left + YEAST_TRNA_PHE + right          # 真核 tRNA 阳性区（~516 bp）
    contig2 = rand_seq(rng, 700, gc=0.40)            # 纯随机阴性对照

    records = [
        ("scerevisiae_trna_region", contig1),
        ("random_negative", contig2),
    ]
    write_fasta(outdir / "genome.fa", records)

    total = sum(len(s) for _, s in records)
    print(f"已生成测试数据 -> {outdir}（genome.fa 共 {total} bp / {len(records)} 条 contig，"
          f"内含 1 条经典酵母 tRNA-Phe 76 nt）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
