#!/usr/bin/env python3
"""生成 mirdeep2 native 测试用的合成输入。

miRDeep2 需要真实深度测序 reads + 基因组 + miRBase 参考才能产出 miRNA 预测；
合成数据只用于 run_test.sh 做「argv 构造验证」，不覆盖真实计算。

产出（命名对齐上游 TUTORIAL.md）：
  <outdir>/reads.fa                     深度测序 reads（FASTA）
  <outdir>/cel_cluster.fa               参考基因组（占位）
  <outdir>/reads_collapsed.fa           mapper -s 产物（占位）
  <outdir>/reads_collapsed_vs_genome.arf mapper -t 产物（占位）
  <outdir>/mature_ref_this_species.fa   本物种 mature 参考（占位）
  <outdir>/mature_ref_other_species.fa  近缘物种 mature 参考（占位）
  <outdir>/precursors_ref_this_species.fa 本物种 precursor 参考（占位）
"""
from __future__ import annotations

import sys
from pathlib import Path

_READS = (
    ">read_1\nUGAGGUAGUAGGUUGUAUAGUU\n"
    ">read_2\nUGAGGUAGUAGGUUGUAUAGUU\n"
    ">read_3\nUUCACAGUGGCUAAGUUCUGC\n"
)
_GENOME = ">cel_cluster_test\n" + ("ACGTACGTACGTACGTACGTACGTACGTACGTACGT\n" * 4)
_MATURE = ">cel-miR-test\nUGAGGUAGUAGGUUGUAUAGUU\n"
_PRECURSOR = ">cel-mir-test\n" + ("ACGTACGTACGTACGTACGTACGTACGTACGT\n" * 3)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "reads.fa").write_text(_READS, encoding="utf-8")
    (outdir / "cel_cluster.fa").write_text(_GENOME, encoding="utf-8")
    (outdir / "reads_collapsed.fa").write_text(_READS, encoding="utf-8")
    (outdir / "reads_collapsed_vs_genome.arf").write_text(
        "# arf placeholder\ntest\n", encoding="utf-8"
    )
    (outdir / "mature_ref_this_species.fa").write_text(_MATURE, encoding="utf-8")
    (outdir / "mature_ref_other_species.fa").write_text(
        ">cbr-miR-test\nUGAGGUAGUAGGUUGUAUAGUU\n", encoding="utf-8"
    )
    (outdir / "precursors_ref_this_species.fa").write_text(_PRECURSOR, encoding="utf-8")
    print(f"已生成 mirdeep2 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
