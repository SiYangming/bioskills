#!/usr/bin/env python3
"""生成 repeatmasker native 测试用的合成小基因组 + 迷你自定义重复库。

产出（<outdir> 下）：
  genome.fa     合成小基因组（5 条 contig，总长约 5~6 kb）：在随机「类基因」骨架中
                散布 ALU_LIKE / LINE_LIKE 共有序列的变异拷贝，并混入 (AT)n 简单串联
                与 poly-A 低复杂度区，模拟可被 -lib 屏蔽/注释的微型基因组。
  consensi.fa   迷你自定义重复库：ALU_LIKE / LINE_LIKE 两条共有序列
                （RepeatModeler consensi.fa 的简化风格），供 -lib 屏蔽回归使用。

说明：
- 动态生成、体积 <10KB；仅用于 run_test.sh 的参数/自省回归，及教学/未来在装有
  RepeatMasker 的机器上用 -lib 模式做真实屏蔽自测（该模式无需 Dfam/RepBase 库）。
- 序列固定（seed=20260909），可重复断言。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 20260909

# 迷你重复库条目：(fasta 名, GC 比例, 共有序列长度)
_LIB_ENTRIES = [
    ("ALU_LIKE#SINE/Alu", 0.55, 220),
    ("LINE_LIKE#LINE/L1", 0.45, 300),
]


def rand_seq(rng: random.Random, length: int, gc: float) -> str:
    """生成伪随机 DNA 片段（gc 为 GC 比例）。"""
    pool = "GC" * int(round(gc * 10)) + "AT" * int(round((1 - gc) * 10))
    return "".join(rng.choice(pool) for _ in range(length))


def mutate(rng: random.Random, seq: str, rate: float = 0.05) -> str:
    """对共有序列做少量替换，模拟真实拷贝（默认 5% 分歧）。"""
    return "".join(
        rng.choice("ACGT") if rng.random() < rate else b for b in seq
    )


def make_contig(rng: random.Random, length: int, cons_by_gc: dict[float, str]) -> str:
    """随机类基因骨架 + 散布的重复拷贝 + 简单重复/低复杂度区拼接成一条 contig。"""
    parts: list[str] = []
    cons_seqs = list(cons_by_gc.values())
    while sum(len(p) for p in parts) < length:
        parts.append(rand_seq(rng, rng.randint(50, 130), gc=0.40))      # 类基因随机区
        kind = rng.randrange(4)
        if kind == 0:
            parts.append(mutate(rng, rng.choice(cons_seqs)))             # 散布式重复拷贝
        elif kind == 1:
            parts.append("AT" * rng.randint(12, 40))                     # 简单串联 (AT)n
        elif kind == 2:
            parts.append("A" * rng.randint(15, 45))                      # 低复杂度 poly-A
        else:
            parts.append(rand_seq(rng, rng.randint(60, 140), gc=0.42))   # 普通随机区
    return "".join(parts)[:length]


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

    rng = random.Random(_SEED)
    # 1) 生成两条共有序列（同一 rng 流，genome 的拷贝与 consensi.fa 保持一致）
    cons_by_gc: dict[float, str] = {}
    lib_records: list[tuple[str, str]] = []
    for name, gc, length in _LIB_ENTRIES:
        seq = rand_seq(rng, length, gc)
        cons_by_gc[gc] = seq
        lib_records.append((name, seq))
    write_fasta(outdir / "consensi.fa", lib_records)

    # 2) 5 条 contig：骨架 + 上述拷贝的变异体（拷贝来源按 gc 匹配）
    contigs = [("chr1_scaffold", 1300), ("chr2_scaffold", 1200),
               ("chr3_scaffold", 1100), ("chr4_scaffold", 1000), ("chr5_scaffold", 900)]
    genome_records: list[tuple[str, str]] = []
    for name, length in contigs:
        genome_records.append((name, make_contig(rng, length, cons_by_gc)))
    write_fasta(outdir / "genome.fa", genome_records)

    total = sum(len(s) for _, s in genome_records)
    print(f"已生成测试数据 -> {outdir}（genome.fa 共 {total} bp / 5 条 contig；consensi.fa 迷你库 {len(lib_records)} 条）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
