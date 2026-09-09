#!/usr/bin/env python3
"""生成 musket native 测试用的合成多文库 FASTQ 数据。

产出（全部纯 Python 生成，保持仓库轻量）：
  <outdir>/f1.fastq   文库 1（4 条 reads，64 bp）
  <outdir>/f2.fastq   文库 2（4 条 reads，64 bp，与 f1 序列不同）

数据设计：每条序列 64 bp（> 默认 MAX_KMER_SIZE 28 与测试用 k=21 均满足）；由 4 bp 重复单元
确定性生成（0/1/2/3 位错开，保证条条不同）；错误注入：文库 1 第 2 条 reads 的第 31 位（1-based）
与文库 2 第 2 条 reads 的第 25 位各放 1 个替换错误（A→C / C→T 方向由原碱基决定），模拟低覆盖区
的测序替换错误——Musket 的修正对象。Musket 真跑冒烟只断言「命令成功且输出非空」（是否真的改掉
该碱基不作为断言项，避免对极小数据下 k-mer 谱行为的过度假设）。

不依赖 musket 二进制；仅标准库。序列只含 ACGT、质量行统一 'I'（Phred+33 高质）。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 两条重复单元模板（4 bp × 16 = 64 bp）；偏移 1/2/3 保证同文库内序列互不相同
def _seq(unit: str, off: int) -> str:
    shifted = (unit[off:] + unit[:off]) if off else unit
    return shifted * 16


_F1_UNITS = ["ACGT", "TGCA", "GGGA", "TTTC"]
_F2_UNITS = ["AACC", "CCTT", "GATC", "ATCG"]

# 替换错误注入：返回把 seq 的 1-based pos 位替换为互补换碱基（A<->C / G<->T）的新序列
_MUT = {"A": "C", "C": "A", "G": "T", "T": "G"}


def _inject_error(seq: str, pos1: int) -> str:
    i = pos1 - 1
    assert 0 <= i < len(seq), f"错误注入位置越界: {pos1}"
    orig = seq[i]
    return seq[:i] + _MUT[orig] + seq[i + 1:]


def _check(seq: str) -> None:
    assert len(seq) == 64, f"序列长度必须 64（收到 {len(seq)}）"
    assert set(seq) <= set("ACGT"), f"序列只允许 ACGT: {seq}"


def _write_fastq(path: Path, reads: list[str]) -> int:
    with open(path, "w") as fh:
        for i, seq in enumerate(reads, start=1):
            _check(seq)
            fh.write(f"@r{i}\n{seq}\n+\n{'I' * len(seq)}\n")
    return len(reads)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    # 文库 1 / 文库 2 各 4 条 64 bp reads（第 2 条注入 1 个替换错误）
    f1 = [_seq(u, i) for i, u in enumerate(_F1_UNITS)]
    f2 = [_seq(u, i) for i, u in enumerate(_F2_UNITS)]
    f1[1] = _inject_error(f1[1], 31)   # 第 31 位（1-based）替换错误
    f2[1] = _inject_error(f2[1], 25)   # 第 25 位（1-based）替换错误

    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    n1 = _write_fastq(outdir / "f1.fastq", f1)
    n2 = _write_fastq(outdir / "f2.fastq", f2)
    print(f"已生成测试数据 -> {outdir}（f1={n1} 条 / f2={n2} 条 reads，各含 1 条带替换错误的 read）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
