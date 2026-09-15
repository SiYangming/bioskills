#!/usr/bin/env python3
"""生成 Platanus-allee native 测试用的合成输入。

Platanus-allee 的 assemble/phase/consensus 都需要真实测序数据才能产出结果，合成数据无法
覆盖真实计算，因此本脚本生成「结构合法的最小合成文件」，供 run_test.sh 做 argv 构造断言；
若本机已安装 platanus_allee，则可用这些文件验证命令构建（真实组装需大规模数据）。

产出：
  <outdir>/illumina.1.fastq   合成短读 R1（FASTQ）
  <outdir>/illumina.2.fastq   合成短读 R2（FASTQ）
  <outdir>/subreads.fasta     合成三代长读（FASTA）
  <outdir>/out_contig.fa      assemble 风格 contig（FASTA）
  <outdir>/out_junctionKmer.fa junctionKmer 占位（FASTA）
  <outdir>/out_primaryBubble.fa / out_nonBubbleHomoCandidate.fa  phase 产物风格占位（FASTA）
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with open(outdir / "illumina.1.fastq", "w", encoding="utf-8") as fh:
        for i in range(1, 5):
            fh.write(f"@read{i}/1\n{SEQ}\n+\n{'I' * len(SEQ)}\n")
    with open(outdir / "illumina.2.fastq", "w", encoding="utf-8") as fh:
        for i in range(1, 5):
            fh.write(f"@read{i}/2\n{SEQ[::-1]}\n+\n{'I' * len(SEQ)}\n")

    (outdir / "subreads.fasta").write_text(
        f">subread1\n{SEQ}{SEQ}\n>subread2\n{longer()}\n", encoding="utf-8"
    )
    (outdir / "out_contig.fa").write_text(
        f">ctg1\n{SEQ}{SEQ}\n>ctg2\n{longer()}\n", encoding="utf-8"
    )
    (outdir / "out_junctionKmer.fa").write_text(
        f">jk1\n{SEQ[:32]}\n", encoding="utf-8"
    )
    (outdir / "out_primaryBubble.fa").write_text(
        f">pb1\n{longer()}\n", encoding="utf-8"
    )
    (outdir / "out_nonBubbleHomoCandidate.fa").write_text(
        f">nb1\n{SEQ}{SEQ}\n", encoding="utf-8"
    )
    print(f"已生成 Platanus-allee 测试合成数据 -> {outdir}")
    return 0


def longer() -> str:
    """一条更长的合成序列。"""
    return SEQ + "TTGCAAGCTTAGCTAGCTAGCATCGATCGATCGATCGTAGCTAGCTAGCATCGATCGA"


if __name__ == "__main__":
    raise SystemExit(main())
