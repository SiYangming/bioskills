#!/usr/bin/env python3
"""生成 genemark-es native 测试用的合成输入。

GeneMark-ES/ET 的真实预测需要真实基因组（且运行需 ~/.gm_key），合成数据无法覆盖真实计算；
因此本脚本生成「最小合法 FASTA/GFF 占位」，run_test.sh 在 gmes_petap.pl 未安装时退化为
「python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta    最小基因组 multi-FASTA（es/et --sequence 输入）
  <outdir>/hints.gff       AUGUSTUS 风格 hints GFF（convert_hints 输入）
  <outdir>/introns.gff     GeneMark-ET 内含子 hints GFF（et --ET 输入）
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
        "ATGGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAA\n"
        "ATGGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAA\n",
        encoding="utf-8",
    )
    (outdir / "hints.gff").write_text(
        "chr1\thints\tintron\t10\t30\t.\t+\t.\t\n", encoding="utf-8"
    )
    (outdir / "introns.gff").write_text(
        "chr1\tGeneMark.hmm\tintron\t10\t30\t.\t+\t.\t\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
