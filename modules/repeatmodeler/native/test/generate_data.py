#!/usr/bin/env python3
"""生成 repeatmodeler native 测试用的合成小基因组。

产出（<outdir>/genome.fa）：
  10 条微型 contig（每条 200~800 bp，总长约 5~6 kb），每条由「类基因随机区 +
  串联/低复杂度重复阵列」拼接而成，模拟含简单重复（AT 富集）、低复杂度、
  散布式 GC 富集拷贝的微型基因组。

说明：
- 动态生成、体积 <10KB，仅用于 run_test.sh 的 BuildDatabase→RepeatModeler
  最小链路回归（RepeatModeler 完整建库面向真实基因组需数十 GB 计算与完整依赖，
  本数据不用于真实 repeat 建模结论）。
- 序列固定（seed=20260909），可重复断言。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 20260909


def rand_seq(rng: random.Random, length: int, gc: float = 0.42) -> str:
    """生成伪随机 DNA 片段（gc 为 GC 比例）。"""
    pool = "GC" * int(round(gc * 10)) + "AT" * int(round((1 - gc) * 10))
    return "".join(rng.choice(pool) for _ in range(length))


def make_contig(rng: random.Random, name: str, length: int) -> str:
    """类基因随机区 + 重复阵列交替拼接成一条 contig。"""
    parts: list[str] = []
    while sum(len(p) for p in parts) < length:
        # 类基因随机区（60~140 bp）
        parts.append(rand_seq(rng, rng.randint(60, 140)))
        # 重复阵列：交替选择 AT 二核苷酸 / 多聚 A / GC 富集拷贝
        kind = rng.randrange(3)
        if kind == 0:
            parts.append("AT" * rng.randint(15, 50))                 # 简单串联 (AT)n
        elif kind == 1:
            parts.append("A" * rng.randint(20, 60))                  # 低复杂度 poly-A
        else:
            parts.append(rand_seq(rng, rng.randint(40, 90), gc=0.72))  # GC 富集散布拷贝
    seq = "".join(parts)[:length]
    _ = name  # contig 名保留在 fasta 头；长度不足时按截断处理
    return seq


def write_fasta(path: Path) -> None:
    rng = random.Random(_SEED)
    contigs = [
        ("chr1_simple_repeat", 800),
        ("chr2_at_enriched", 720),
        ("chr3_gc_copy", 660),
        ("chr4_polyA_lowcomp", 600),
        ("chr5_mosaic", 640),
        ("chr6_mosaic", 620),
        ("chr7_rand", 580),
        ("chr8_rand", 560),
        ("scaffold9", 520),
        ("scaffold10", 500),
    ]
    with open(path, "w") as fh:
        for name, length in contigs:
            fh.write(f">{name}\n")
            seq = make_contig(rng, name, length)
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "genome.fa")
    total = sum(len(line.strip()) for line in (outdir / "genome.fa").read_text().splitlines()
                if not line.startswith(">"))
    print(f"已生成合成小基因组 -> {outdir / 'genome.fa'}（共 {total} bp，10 条 contig）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
