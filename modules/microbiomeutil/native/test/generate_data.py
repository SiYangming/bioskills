#!/usr/bin/env python3
"""生成 microbiomeutil native 测试用的合成 16S 输入。

全部为确定性合成序列，保持仓库轻量（ChimeraSlayer 真实运行需 megablast 参考库与
cdbtools，属重依赖；run_test.sh 因此以 argv 构造断言为主）：
  <outdir>/query.fasta   未比对查询序列（nastier 输入）
  <outdir>/query.NAST    NAST 比对格式查询（chimeraslayer / wigeon 输入）
  <outdir>/ref.fasta     参考库 FASTA
  <outdir>/ref.NAST      参考库 NAST 比对格式
"""
from __future__ import annotations

import sys
from pathlib import Path

# 确定性 16S 样序列（约 60 bp）
QUERIES = {
    "q1": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC",
    "q2": "AGAGTTTGATCCTGGCTCAGGATGAACGCTAGCGGCAGGCCTAACACATGCAAGTCGAAC",
    "q3": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCATGCCTAACACATGCAAGTCGAGC",
}
# NAST 风格：对齐后插入 gap（'-'）占位
QUERIES_NAST = {
    "q1": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC---------",
    "q2": "AGAGTTTGATCCTGGCTCAGGATGAACGCTAGCGGCAGGCCTAACACATGCAAGTCGAAC---------",
    "q3": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCATGCCTAACACATGCAAGTCGAGC---------",
}
REFS = {
    "r1": "AGAGTTTGATCCTGGCTCAGAATGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC",
    "r2": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC",
}
REFS_NAST = {
    "r1": "AGAGTTTGATCCTGGCTCAGAATGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC---------",
    "r2": "AGAGTTTGATCCTGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAAC---------",
}


def write_fasta(path: Path, records: dict) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        for name, seq in records.items():
            fh.write(f">{name}\n{seq}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    write_fasta(outdir / "query.fasta", QUERIES)
    write_fasta(outdir / "query.NAST", QUERIES_NAST)
    write_fasta(outdir / "ref.fasta", REFS)
    write_fasta(outdir / "ref.NAST", REFS_NAST)

    print(f"已生成 microbiomeutil 合成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
