#!/usr/bin/env python3
"""生成 ea-utils native 测试用的合成 FASTQ / 接头数据。

全部为确定性合成序列，不依赖外部下载，保持仓库轻量：
  <outdir>/r1.fastq        R1（片段前 70 bp）
  <outdir>/r2.fastq        R2（片段 40–110 bp 的反向互补，与 R1 有 30 bp 重叠）
  <outdir>/single.fastq    单端 FASTQ（末条 3' 端含接头，供 clipper 真实切除）
  <outdir>/adapters.fa     接头序列（FASTA）

fastq-join 需要真实成对数据才能拼接；本脚本构造的重叠对可让已安装 fastq-join
真实拼接出 1 条 read（run_test.sh 在二进制缺失时退化为 argv 构造断言）。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 确定性片段（120 bp；避免使用随机数以保证可复现）
FRAGMENT = (
    "ACGTACGTACGTACGTTGCACGTAGCTAGCTAGGCTAACGTACGATCGTAGCTAGCATCGATCGTAGC"
    "TTAGCGATCGATCGTAGCTAGCTAGCATCGATCGATCGTAGCTAGCTAGCATCGATCGTAG"
)
ADAPTER = "AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC"

_COMP = str.maketrans("ACGTNacgtn", "TGCANtgcan")


def revcomp(seq: str) -> str:
    return seq.translate(_COMP)[::-1]


def fq_record(name: str, seq: str, qual: str) -> str:
    return f"@{name}\n{seq}\n+\n{qual}\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    frag = (FRAGMENT * 2)[:120]
    r1 = frag[0:70]
    r2 = revcomp(frag[40:110])  # 与 R1 重叠 30 bp
    q1 = "I" * len(r1)
    q2 = "I" * len(r2)

    (outdir / "r1.fastq").write_text(fq_record("read1/1", r1, q1), encoding="utf-8")
    (outdir / "r2.fastq").write_text(fq_record("read1/2", r2, q2), encoding="utf-8")

    # 单端数据：两条正常 read + 一条 3' 端带接头的 read（clipper 可真实切除）
    s1 = "ACGTACGTACGTACGTACGTACGTACGTACGT"
    s2 = "TTGCAAGCTAGCTAGCATCGATCGATCGTAGC"
    s3 = "GGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAA" + ADAPTER
    single = (
        fq_record("s1", s1, "I" * len(s1))
        + fq_record("s2", s2, "I" * len(s2))
        + fq_record("s3", s3, "I" * len(s3))
    )
    (outdir / "single.fastq").write_text(single, encoding="utf-8")

    (outdir / "adapters.fa").write_text(
        f">adapter1\n{ADAPTER}\n", encoding="utf-8"
    )

    print(f"已生成 ea-utils 合成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
