#!/usr/bin/env python3
"""生成 usearch native 测试用的合成 FASTA。

全部为确定性合成序列，保持仓库轻量（USEARCH 8 为预编译二进制，run_test.sh 在
二进制缺失时退化为 argv 构造断言）：
  <outdir>/seqs.fa       待去冗余/聚类序列（含 ;size=N 丰度标签，供 de novo 嵌合体检测）
  <outdir>/ref.fa        参考库序列（uchime_ref / usearch_global 的 -db）
  <outdir>/uniques.fa    已去冗余序列（cluster_otus 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQS = {
    "s1": ("AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC", 12),
    "s2": ("AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAT", 5),
    "s3": ("AGAGTTTGATCCTGGCTCAGGATGAACGCTAGCGGCAGGCCTAACACATGCAAGTCGAAC", 3),
    "s4": ("TTGCAAGCTAGCTAGCATCGATCGATCGTAGCTAGCATCGATCGTAGCTAGCATCGATCGA", 2),
}
REFS = {
    "r1": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC",
    "r2": "AGAGTTTGATCCTGGCTCAGGATGAACGCTAGCGGCAGGCCTAACACATGCAAGTCGAAC",
}


def write_fasta(path: Path, records: dict, with_size: bool = False) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        for name, val in records.items():
            if with_size and isinstance(val, tuple):
                seq, size = val
                fh.write(f">{name};size={size}\n{seq}\n")
            else:
                fh.write(f">{name}\n{val}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    write_fasta(outdir / "seqs.fa", SEQS, with_size=True)
    write_fasta(outdir / "ref.fa", REFS)
    # uniques：去掉 size 标签供 cluster_otus（去噪聚类）使用
    write_fasta(outdir / "uniques.fa", {k: v[0] for k, v in SEQS.items()})

    print(f"已生成 usearch 合成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
