#!/usr/bin/env python3
"""生成 fastp native 测试用的合成 FASTQ.gz 数据。

fastp 需要真实 FASTQ 才能产出清洗结果，合成数据无法覆盖真实计算，
因此本脚本生成一个小型、确定的双端 FASTQ（read 3' 端带 Illumina 通用接头），
run_test.sh 在 fastp 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」，
不执行真实 fastp；若二进制已安装则额外做 --version 冒烟。

产出：
  <outdir>/R1.fq.gz   R1（4 条，110 nt = 88 nt 插入 + 22 nt 接头，Q=40）
  <outdir>/R2.fq.gz   R2（4 条，同上，接头为 R1 反向互补）
"""
from __future__ import annotations

import gzip
import random
import sys
from pathlib import Path

RNG = random.Random(42)  # 固定种子，输出确定

ADAPTER_R1 = "AGATCGGAAGAGCACACGTCTGA"          # Illumina TruSeq 通用接头
ADAPTER_R2 = "TCAGACGTGTGCTCTTCCGATCT"          # 反向互补
INSERT_LEN = 88
QUAL = "I" * (INSERT_LEN + len(ADAPTER_R1))     # Phred 40 全高质量

BASES = "ACGT"


def random_seq(n: int) -> str:
    return "".join(RNG.choice(BASES) for _ in range(n))


def write_fastq_gz(path: Path, reads: list[tuple[str, str, str]]) -> None:
    """reads: [(name, seq, qual)]"""
    with gzip.open(path, "wt", encoding="utf-8") as fh:
        for name, seq, qual in reads:
            fh.write(f"@{name}\n{seq}\n+\n{qual}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    r1_reads: list[tuple[str, str, str]] = []
    r2_reads: list[tuple[str, str, str]] = []
    for i in range(1, 5):
        insert = random_seq(INSERT_LEN)
        r1_reads.append(
            (f"read{i}/1", insert + ADAPTER_R1, QUAL)
        )
        r2_reads.append(
            (f"read{i}/2", random_seq(INSERT_LEN) + ADAPTER_R2, QUAL)
        )

    write_fastq_gz(outdir / "R1.fq.gz", r1_reads)
    write_fastq_gz(outdir / "R2.fq.gz", r2_reads)
    print(f"已生成测试数据 -> {outdir}/R1.fq.gz, {outdir}/R2.fq.gz")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
