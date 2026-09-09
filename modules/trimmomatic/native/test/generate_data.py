#!/usr/bin/env python3
"""生成 Trimmomatic 回归测试用最小合成 FASTQ 数据。

产出（outdir 内）：
  test_se.fq        3 条单端 reads（2 条 32bp 全长、1 条 8bp 超短）
  test_pe_R1.fq.gz  3 条 R1（paired R1/R2 同名同序）
  test_pe_R2.fq.gz  3 条 R2

设计意图：
- 全部碱基质量用 'I'(Q40)，保证 LEADING:3/TRAILING:3 不会误切除；
- 含 1 条 8bp 超短 read，配合 MINLEN 验证"长度过滤"路径；
- PE 同名同序配对，可验证 paired/unpaired 分流逻辑。
只生成文件不执行 trimmomatic（真实运行与否由 run_test.sh 按环境探测决定）。
"""

from __future__ import annotations

import argparse
import gzip
import random
from pathlib import Path


def fq_record(name: str, seq: str, qual_char: str = "I") -> str:
    return f"@{name}\n{seq}\n+\n{qual_char * len(seq)}\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-o", "--outdir", default=".", help="输出目录（默认当前目录）")
    ns = ap.parse_args()
    out = Path(ns.outdir)
    out.mkdir(parents=True, exist_ok=True)

    rng = random.Random(42)
    # 固定序列保证可复现；32bp（pass MINLEN:20）/ 8bp（fail MINLEN:20）
    seqs_se = [
        "ACGTACGTACGTACGTACGTACGTACGTACGT",   # 32bp -> survive
        "GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG",   # 32bp -> survive
        "TTTTGGGG",                            # 8bp  -> MINLEN drop
    ]
    seqs_r1 = [
        "ACGTACGTACGTACGTACGTACGTACGTACGT",
        "GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG",
        "TTTTGGGG",
    ]
    seqs_r2 = [
        "TGCATGCATGCATGCATGCATGCATGCATGCA",
        "CGATCGATCGATCGATCGATCGATCGATCGATC",
        "AAAACCCC",
    ]
    # 轻微打乱但不影响 minlen 逻辑（保持确定性，仅展示可随机）
    rng.shuffle(seqs_se)

    se = "".join(fq_record(f"se_r{i}", s) for i, s in enumerate(seqs_se))
    (out / "test_se.fq").write_text(se, encoding="utf-8")

    def _pe(lines_r1: list[str], lines_r2: list[str]) -> tuple[str, str]:
        r1 = "".join(fq_record(f"pe_r{i}", s) for i, s in enumerate(lines_r1))
        r2 = "".join(fq_record(f"pe_r{i}", s) for i, s in enumerate(lines_r2))
        return r1, r2

    r1, r2 = _pe(seqs_r1, seqs_r2)
    with gzip.open(out / "test_pe_R1.fq.gz", "wt", encoding="utf-8") as fh:
        fh.write(r1)
    with gzip.open(out / "test_pe_R2.fq.gz", "wt", encoding="utf-8") as fh:
        fh.write(r2)

    print(f"已生成: {out}/test_se.fq, {out}/test_pe_R1.fq.gz, {out}/test_pe_R2.fq.gz")


if __name__ == "__main__":
    main()
