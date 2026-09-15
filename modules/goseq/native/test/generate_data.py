#!/usr/bin/env python3
"""生成 goseq native 测试用合成数据。

goseq 需要真实的差异基因列表 + 基因长度 + GO 映射才能产出富集结果，合成数据无法覆盖
真实统计计算。因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv
验证命令构建不崩溃（monkeypatch _resolve_binary，不依赖已安装 R/goseq）。

产出（<outdir> 下，均为 Tab 分隔）：
  gene_lengths.tsv  基因长度表（首列 gene id、次列长度；全部被检验基因）
  de_genes.txt      差异基因列表（gene_lengths 的子集，每行一个 id）
  gene2go.tsv       基因→GO 类别映射（次列多个类别用 ; 分隔）
"""
from __future__ import annotations

import sys
from pathlib import Path

GENES = [f"gene_{i:02d}" for i in range(1, 11)]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    with open(outdir / "gene_lengths.tsv", "w", encoding="utf-8") as fh:
        for i, g in enumerate(GENES):
            fh.write(f"{g}\t{500 + i * 120}\n")

    (outdir / "de_genes.txt").write_text(
        "\n".join(GENES[:5]) + "\n", encoding="utf-8"
    )

    with open(outdir / "gene2go.tsv", "w", encoding="utf-8") as fh:
        fh.write("gene_01\tGO:0008150;GO:0009987\n")
        fh.write("gene_02\tGO:0008150\n")
        fh.write("gene_03\tGO:0003674;GO:0005488\n")
        fh.write("gene_04\tGO:0005575\n")
        fh.write("gene_05\tGO:0008150;GO:0003674\n")
        fh.write("gene_06\tGO:0009987\n")
        fh.write("gene_07\tGO:0005488\n")
        fh.write("gene_08\tGO:0005575\n")
        fh.write("gene_09\tGO:0003674\n")
        fh.write("gene_10\tGO:0008150\n")

    print(f"已生成 goseq 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
