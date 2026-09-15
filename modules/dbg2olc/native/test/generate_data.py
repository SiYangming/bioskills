#!/usr/bin/env python3
"""生成 DBG2OLC native 测试用的合成输入。

DBG2OLC 三段链路（SparseAssembler -> DBG2OLC -> Sparc）都需要真实测序数据才能产出结果，
合成数据无法覆盖真实计算，因此本脚本生成「结构合法的最小合成文件」，供 run_test.sh 做
argv 构造断言；若本机已安装 DBG2OLC，则额外用这些文件跑一次真实冒烟。

产出：
  <outdir>/illumina.1.fastq      合成短读 R1（FASTQ）
  <outdir>/illumina.2.fastq      合成短读 R2（FASTQ）
  <outdir>/subreads.fasta        合成三代长读（FASTA）
  <outdir>/Contigs.txt           SparseAssembler 风格的合成 contigs（FASTA）
  <outdir>/backbone_raw.fasta    DBG2OLC 风格 backbone（FASTA）
  <outdir>/DBG2OLC_Consensus_info.txt  consensus 信息占位
  <outdir>/ctg_pb.fasta          contigs + 长读合并（FASTA）
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

    # 合成短读（4 条）
    with open(outdir / "illumina.1.fastq", "w", encoding="utf-8") as fh:
        for i in range(1, 5):
            fh.write(f"@read{i}/1\n{SEQ}\n+\n{'I' * len(SEQ)}\n")
    with open(outdir / "illumina.2.fastq", "w", encoding="utf-8") as fh:
        for i in range(1, 5):
            fh.write(f"@read{i}/2\n{SEQ[::-1]}\n+\n{'I' * len(SEQ)}\n")

    # 合成三代长读（2 条）
    with open(outdir / "subreads.fasta", "w", encoding="utf-8") as fh:
        fh.write(f">subread1\n{SEQ}{SEQ}\n{subread_genome()}\n")
        fh.write(f">subread2\n{subread_genome()}\n")

    # SparseAssembler 风格 contigs
    (outdir / "Contigs.txt").write_text(
        f">contig1\n{SEQ}{SEQ}\n>contig2\n{subread_genome()}\n", encoding="utf-8"
    )
    # DBG2OLC 风格 backbone
    (outdir / "backbone_raw.fasta").write_text(
        f">backbone1\n{SEQ}{SEQ}{SEQ}\n", encoding="utf-8"
    )
    # consensus 信息占位
    (outdir / "DBG2OLC_Consensus_info.txt").write_text(
        "backbone1\tcontig1\t0\t128\t+\n", encoding="utf-8"
    )
    # ctg_pb = contigs + 长读
    (outdir / "ctg_pb.fasta").write_text(
        (outdir / "Contigs.txt").read_text(encoding="utf-8")
        + (outdir / "subreads.fasta").read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    print(f"已生成 DBG2OLC 测试合成数据 -> {outdir}")
    return 0


def subread_genome() -> str:
    """一条更长的合成序列（用于长读/contig）。"""
    return SEQ + "TTGCAAGCTTAGCTAGCTAGCATCGATCGATCGATCGTAGCTAGCTAGCATCGATCGA"


if __name__ == "__main__":
    raise SystemExit(main())
