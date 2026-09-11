#!/usr/bin/env python3
"""生成 blast（NCBI BLAST+）native 测试用的合成数据。

产出（<outdir> 下）：
  ref_nucl.fa   核苷酸参考库（两条 contig：1000 bp / 800 bp）
  query_nucl.fa 单条核苷酸查询（ref_nucl 第一条 contig 的 120 bp 精确子串）
  ref_prot.fa   蛋白参考库（两条蛋白：200 aa / 160 aa）
  query_prot.fa 单条蛋白查询（ref_prot 第一条蛋白的 60 aa 精确子串）

说明：查询取参考的精确子串，保证能在任一小库上产生显著命中；
序列用固定随机种子生成，避免低复杂度导致 blastn 默认 dust 过滤意外屏蔽。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

DNA = "ACGT"
AA = "ACDEFGHIKLMNPQRSTVWY"


def rand_seq(rng: random.Random, alphabet: str, n: int) -> str:
    return "".join(rng.choice(alphabet) for _ in range(n))


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

    # 核苷酸库
    rng = random.Random(42)
    nucl1 = rand_seq(rng, DNA, 1000)
    nucl2 = rand_seq(rng, DNA, 800)
    write_fasta(outdir / "ref_nucl.fa", [("contig1", nucl1), ("contig2", nucl2)])
    write_fasta(outdir / "query_nucl.fa", [("q_nucl1", nucl1[200:320])])

    # 蛋白库
    rng = random.Random(7)
    prot1 = rand_seq(rng, AA, 200)
    prot2 = rand_seq(rng, AA, 160)
    write_fasta(outdir / "ref_prot.fa", [("protein1", prot1), ("protein2", prot2)])
    write_fasta(outdir / "query_prot.fa", [("q_prot1", prot1[50:110])])

    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
