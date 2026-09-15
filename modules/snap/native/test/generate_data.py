#!/usr/bin/env python3
"""生成 snap native 测试用的合成输入。

SNAP 的 fathom/forge/hmm-assembler.pl/snap 需要真实基因组与训练基因模型才能覆盖真实计算，
合成数据无法覆盖。因此本脚本生成「最小占位 + 说明」，run_test.sh 以 python 构造 argv 验证
命令构建（monkeypatch 二进制路径）为主，不依赖 SNAP 真实安装。

产出：
  <outdir>/genome.fasta        最小基因组 FASTA
  <outdir>/genome.ann          ZFF 占位注释（fathom 输入）
  <outdir>/genome.dna          与注释对应的序列占位
  <outdir>/export.ann          训练导出注释占位（forge 输入）
  <outdir>/export.dna          训练导出序列占位（forge 输入）
  <outdir>/params/              HMM 参数目录占位（hmm-assembler.pl 输入）
  <outdir>/species.hmm         HMM 模型占位（snap predict 输入）
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

    (outdir / "genome.fasta").write_text(
        ">chr1\n"
        "ATGGCAGGTACGTACGTACGTACGTAGCTAGCTAGCATCGATCGATCGTAGCTAGCTAGCTAGCATCG\n"
        ">chr2\n"
        "ATGTTTGGGCCCAAATTTGGGCCCAAATTTGGGCCCAAATTTGGGCCCAAATTTGGGCCCAAATTT\n",
        encoding="utf-8",
    )
    (outdir / "genome.ann").write_text(
        ">SNAP_00000001\n"
        "gene 1 30\n"
        "mRNA 1 30\n"
        "exon 1 12\n"
        "exon 19 30\n"
        "cds 1 12\n"
        "cds 19 30\n",
        encoding="utf-8",
    )
    (outdir / "genome.dna").write_text(
        ">SNAP_00000001\n"
        "ATGGCAGGTACGTACGTACGTACGTAGCT\n",
        encoding="utf-8",
    )
    (outdir / "export.ann").write_text(">SNAP_00000001\n", encoding="utf-8")
    (outdir / "export.dna").write_text(">SNAP_00000001\nATGGCAGGTACGTACG\n", encoding="utf-8")
    (outdir / "params").mkdir(exist_ok=True)
    (outdir / "params" / "README.placeholder").write_text(
        "# PLACEHOLDER: forge 产出的 HMM 参数目录\n", encoding="utf-8"
    )
    (outdir / "species.hmm").write_text(
        "# PLACEHOLDER: SNAP HMM model (hmm-assembler.pl 产物)\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
