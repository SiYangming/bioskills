#!/usr/bin/env python3
"""生成 geta native 测试用的合成输入。

GETA 需要重复序列库 + RNA-seq + 同源蛋白 + AUGUSTUS 物种参数才能跑通，合成数据无法覆盖
真实计算。因此本脚本生成「可被命令构造读取的迷你输入」，run_test.sh 在 GETA 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」（不依赖已安装脚本）。

产出：
  <outdir>/genome.fasta          迷你基因组 FASTA（--genome）
  <outdir>/reads.1.fastq         迷你 RNA-seq 正向 reads（-1）
  <outdir>/reads.2.fastq         迷你 RNA-seq 反向 reads（-2）
  <outdir>/homolog.fasta         迷你同源蛋白 FASTA（--protein）
  <outdir>/consensi.fa           迷你重复序列库占位（--RM_lib）
  <outdir>/Pfam-AB.hmm           迷你 Pfam 库占位（--pfam_db）
  <outdir>/out.gff3              GETA 输出占位（best_models 输入）
  <outdir>/bestGeneModels.gff3   best_models 输出占位（gff3_to_gtf 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

_FASTQ1 = (
    "@r1/1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAA\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"
)
_FASTQ2 = (
    "@r1/2\nTTTGGCTGTCGCGCAATAATAATACGCCGTTTTCAT\n+\nIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "genome.fasta").write_text(
        ">chr1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAATTTCTTTTGTGAAATCTCACTTTTCTCGCCAG\n"
        "CTAGAAGAACGTCTTGGTCTTATTGAAGTTCAGTAA\n",
        encoding="utf-8",
    )
    (outdir / "reads.1.fastq").write_text(_FASTQ1, encoding="utf-8")
    (outdir / "reads.2.fastq").write_text(_FASTQ2, encoding="utf-8")
    (outdir / "homolog.fasta").write_text(
        ">homolog1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n", encoding="utf-8"
    )
    (outdir / "consensi.fa").write_text(
        ">rnd-1_family-1#LINE\nACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8"
    )
    (outdir / "Pfam-AB.hmm").write_text(
        "HMMER3/f\n# 迷你 Pfam 占位（geta --pfam_db 只读路径）\n", encoding="utf-8"
    )
    (outdir / "out.gff3").write_text(
        "##gff-version 3\nchr1\tGETA\tgene\t1\t66\t.\t+\t.\tID=MS01Gene000001\n",
        encoding="utf-8",
    )
    (outdir / "bestGeneModels.gff3").write_text(
        "##gff-version 3\nchr1\tBestGeneModels\tgene\t1\t66\t.\t+\t.\tID=MS01Gene000001\n",
        encoding="utf-8",
    )
    print(f"已生成测试迷你输入 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
