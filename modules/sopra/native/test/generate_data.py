#!/usr/bin/env python3
"""生成 sopra native 测试用的合成输入。

SOPRA scaffolding 需要真实比对结果，合成数据无法覆盖真实计算；本脚本生成「文本占位 +
说明」，供 run_test.sh 做 argv 构造断言（不真实执行 SOPRA 的 Perl 脚本）。

产出：
  <outdir>/contig.fasta             迷你 contigs FASTA
  <outdir>/frag.fasta               fragment（PE）库 FASTA
  <outdir>/jump.fasta               jumping（mate-pair）库 FASTA
  <outdir>/frag_sopra.sam           bowtie2 SAM 占位
  <outdir>/jump_sopra.sam           bowtie2 SAM 占位
  <outdir>/frag_sopra.sam_parsed    parse_sam 产物占位
  <outdir>/jump_sopra.sam_parsed    parse_sam 产物占位
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

    (outdir / "contig.fasta").write_text(
        ">contig1\nACGTACGTACGTACGTACGTACGTACGTACGT\n>contig2\nTTTTGGGGCCCCAAAA\n",
        encoding="utf-8")
    (outdir / "frag.fasta").write_text(">f1\nACGTACGTACGT\n", encoding="utf-8")
    (outdir / "jump.fasta").write_text(">j1\nTTTTGGGGCCCC\n", encoding="utf-8")
    (outdir / "frag_sopra.sam").write_text(
        "@HD\tVN:1.0\n# PLACEHOLDER: bowtie2 frag 比对结果\n", encoding="utf-8")
    (outdir / "jump_sopra.sam").write_text(
        "@HD\tVN:1.0\n# PLACEHOLDER: bowtie2 jump 比对结果\n", encoding="utf-8")
    (outdir / "frag_sopra.sam_parsed").write_text("# PLACEHOLDER parsed\n", encoding="utf-8")
    (outdir / "jump_sopra.sam_parsed").write_text("# PLACEHOLDER parsed\n", encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
