#!/usr/bin/env python3
"""生成 braker native 测试用的合成输入。

BRAKER2 真实运行需 AUGUSTUS/GeneMark/ProtHint/gth 等大量依赖与真实 BAM，无法在测试中覆盖。
本脚本生成最小占位输入，run_test.sh 以 python 构造 argv 验证命令构建（monkeypatch 二进制路径）为主。

产出：
  <outdir>/genome.softmask.fasta   软屏蔽基因组 FASTA
  <outdir>/rnaseq.sort.bam         RNA-seq 比对 BAM 占位
  <outdir>/homolog.fasta           同源蛋白占位
  <outdir>/braker.gtf              最小 GTF（gtf2gff3 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "genome.softmask.fasta").write_text(
        ">scaffold_1\nATGGCAGGTACGTACGTACGTAGCTAGCTAGCATCGATCGATCGTAGCTAGCTAGCTAGCATCG\n",
        encoding="utf-8",
    )
    (outdir / "rnaseq.sort.bam").write_text(
        "# PLACEHOLDER: braker.pl 需要真实 RNA-seq sorted BAM\n", encoding="utf-8"
    )
    (outdir / "homolog.fasta").write_text(
        ">homolog1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n",
        encoding="utf-8",
    )
    (outdir / "braker.gtf").write_text(
        "scaffold_1\tBRAKER1\tgene\t1\t30\t.\t+\t.\tgene_id \"g1\";\n"
        "scaffold_1\tBRAKER1\ttranscript\t1\t30\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "scaffold_1\tBRAKER1\texon\t1\t30\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "scaffold_1\tBRAKER1\tCDS\t1\t30\t.\t+\t0\tgene_id \"g1\"; transcript_id \"t1\";\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
