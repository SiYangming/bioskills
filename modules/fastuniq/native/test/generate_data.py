#!/usr/bin/env python3
"""生成 fastuniq native 测试用的合成配对 FASTQ 数据。

产出（全部纯 Python 生成，保持仓库轻量）：
  <outdir>/reads.R1.fastq   R1（read1）端 3 条 reads
  <outdir>/reads.R2.fastq   R2（read2）端 3 条 reads（与 R1 同序、同数，FastUniq 配对前提）

重复设计（FastUniq 判据：read pair 的 R1+R2 序列两两完全一致 = PCR/光学重复）：
  pair1 = (R1:seqA, R2:seqB)
  pair2 = (R1:seqC, R2:seqD)
  pair3 = (R1:seqA, R2:seqB)  ← 与 pair1 序列完全相同，被视为重复对被去除
→ 去重后应剩 2 个唯一 pair（每端 2 条 reads）。

不依赖 fastuniq 二进制；仅标准库。序列只含 ACGT、质量行统一 'I'（Phred+33 高质）。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 3 条 read pair 的序列（pair3 与 pair1 完全相同 → 去重应剩 2 条/端）
_PAIRS = [
    ("read1", "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT",   # pair1 R1（seqA）
     "TGCATGCAAGCTTGCATGCAAGCTTGCATGCAAGCTTGCATGCAAGCT"),   # pair1 R2（seqB）
    ("read2", "GGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCC",  # pair2 R1（seqC）
     "TTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGG"),      # pair2 R2（seqD）
    ("read3", "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT",     # pair3 R1（=seqA，dup）
     "TGCATGCAAGCTTGCATGCAAGCTTGCATGCAAGCTTGCATGCAAGCT"),     # pair3 R2（=seqB，dup）
]


def _write_fastq(path: Path, mate: int) -> int:
    n = 0
    with open(path, "w") as fh:
        for name, seq1, seq2 in _PAIRS:
            seq = seq1 if mate == 1 else seq2
            fh.write(f"@{name}\n{seq}\n+\n{'I' * len(seq)}\n")
            n += 1
    return n


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    n1 = _write_fastq(outdir / "reads.R1.fastq", 1)
    n2 = _write_fastq(outdir / "reads.R2.fastq", 2)
    assert n1 == n2 == 3, "R1/R2 必须同数同序（FastUniq 配对前提）"
    print(f"已生成测试数据 -> {outdir}（R1/R2 各 {n1} 条 reads；含 1 条重复对）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
