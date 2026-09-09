#!/usr/bin/env python3
"""生成 pacbiotoca（PacBioToCA / PBcR）native 测试用合成数据。

PBcR 混合纠错工作流的输入为：
  - Illumina 双端 FASTQ（→ fastqToCA -mates f1,f2 生成 .frg，trusted 短读）
  - PacBio 长读 FASTA（PBcR -fastq 输入，待纠错；高错误率长序列）

产出（<outdir> 下）：
  reads/r1.fastq, reads/r2.fastq   迷你 Illumina 双端（pair 号一致、可配对）
  pacbio.fasta                     6 条 4–6 kb 级「高噪声」长读（序列按 read 号拼接）
  pacbio.spec                      CA spec 样例（assemble=0：仅纠错不组装）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

RNG = random.Random(42)


def rand_seq(n: int) -> str:
    return "".join(RNG.choice("ACGT") for _ in range(n))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    reads = outdir / "reads"
    reads.mkdir(parents=True, exist_ok=True)

    # 迷你 Illumina 双端：共享 read 号，r1/r2 各自 30 条 × 76 bp
    genome = rand_seq(20000)
    with open(reads / "r1.fastq", "w") as f1, open(reads / "r2.fastq", "w") as f2:
        for i in range(30):
            start = RNG.randrange(0, len(genome) - 152)
            s1, s2 = genome[start:start + 76], genome[start + 76:start + 152]
            q = "I" * 76
            for fh, s in ((f1, s1), (f2, s2)):
                fh.write(f"@illu_{i}/1\n{s}\n+\n{q}\n" if fh is f1 else f"@illu_{i}/2\n{s}\n+\n{q}\n")

    # PacBio 长读 FASTA：6 条，长度 4000–6000（真实 PBcR 输入远长于此，够 argv 演示）
    with open(outdir / "pacbio.fasta", "w") as fh:
        for i in range(6):
            # 以 genome 片段为骨架并掺 12% 随机替代模拟 CLR 噪声（仅形态演示用）
            n = RNG.randrange(4000, 6000)
            seg = list(genome[RNG.randrange(0, len(genome) - n):][:n])
            for j in range(int(n * 0.12)):
                seg[RNG.randrange(n)] = RNG.choice("ACGT")
            fh.write(f">pacbio_read_{i} length={n}\n")
            s = "".join(seg)
            for k in range(0, n, 80):
                fh.write(s[k:k + 80] + "\n")

    # CA spec 样例：assemble=0 → PBcR 仅纠错、不调用 runCA 组装
    with open(outdir / "pacbio.spec", "w") as fh:
        fh.write("# pacbio.spec（bioskills 测试样例；assemble=0 表示仅纠错）\n")
        fh.write("genomeSize = 20000\n")
        fh.write("maxCoverage = 40\n")
        fh.write("assemble = 0\n")

    print(f"已生成 PacBioToCA/PBcR 测试数据 -> {outdir}"
          f"（reads/r1.fastq, reads/r2.fastq, pacbio.fasta, pacbio.spec）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
