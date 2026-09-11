#!/usr/bin/env python3
"""生成 antismash native 测试用的合成数据。

产出（<outdir> 下）：
  genome.gbk  微型合成 GenBank 文件（一条 ~900 bp 随机 contig，含 ORIGIN 序列）

说明：antismash run 需要 GB 级数据库且耗时很长，测试绝不在测试内真跑分析（见
run_test.sh）——genome.gbk 仅用于驱动命令行构造断言 / --dry-run / 未来人工真跑。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 42
CONTIG = "contig00001"
LENGTH = 900


def rand_seq(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_minimal_gbk(path: Path, name: str, seq: str) -> None:
    """写一个最简可被 antismash 读取的 GenBank 文件（CDS 注释留空由 --genefinding 补）。"""
    lines = [
        f"LOCUS       {name:<28s} {len(seq)} bp    DNA     linear   BCT {__import__('datetime').date.today():%d-%b-%Y}",
        "DEFINITION  synthetic minimal genome for antismash skill test.",
        "ACCESSION   " + name,
        "VERSION     " + name + ".1",
        "FEATURES             Location/Qualifiers",
        "     source          1.." + str(len(seq)),
        "                     /organism=\"Synthetic test genome\"",
        "                     /mol_type=\"genomic DNA\"",
        "ORIGIN",
    ]
    upper = seq.upper()
    for i in range(0, len(upper), 60):
        chunk = upper[i:i + 60]
        # GenBank ORIGIN 行：每 10 bp 一组空格分隔
        lines.append("        " + " ".join(chunk[j:j + 10] for j in range(0, len(chunk), 10)))
    lines.append("//")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    write_minimal_gbk(outdir / "genome.gbk", CONTIG, rand_seq(LENGTH, rng))
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
