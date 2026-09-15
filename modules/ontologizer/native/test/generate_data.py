#!/usr/bin/env python3
"""生成 ontologizer native 测试用的合成输入（最小文本占位，保持仓库轻量）。

产出：
  <outdir>/go.obo              最小 GO 本体（3 个顶层 namespace 术语）
  <outdir>/gene_association.gaf 最小 GAF 2.0 关联占位
  <outdir>/S1_vs_S3_S1_UP.list  study set（每行一个基因）
  <outdir>/population.list      population 背景基因
"""
from __future__ import annotations

import sys
from pathlib import Path

GO_OBO = """format-version: 1.2
ontology: go

[Term]
id: GO:0008150
name: biological_process
namespace: biological_process

[Term]
id: GO:0003674
name: molecular_function
namespace: molecular_function

[Term]
id: GO:0005575
name: cellular_component
namespace: cellular_component
"""

# GAF 2.0：17 列制表符分隔（此处仅占位，Ontologizer 真实运行需完整 GAF）
GAF = (
    "!gaf-version: 2.0\n"
    "test\tgene1\tgene1\t\tGO:0008150\tPMID:1\tIDA\t\tP\tgene1\t\tprotein\t\t\t\t\t\n"
    "test\tgene2\tgene2\t\tGO:0003674\tPMID:1\tIDA\t\tF\tgene2\t\tprotein\t\t\t\t\t\n"
    "test\tgene3\tgene3\t\tGO:0005575\tPMID:1\tIDA\t\tC\tgene3\t\tprotein\t\t\t\t\t\n"
)

STUDY = "gene1\ngene2\n"
POPULATION = "gene1\ngene2\ngene3\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "go.obo").write_text(GO_OBO, encoding="utf-8")
    (outdir / "gene_association.gaf").write_text(GAF, encoding="utf-8")
    (outdir / "S1_vs_S3_S1_UP.list").write_text(STUDY, encoding="utf-8")
    (outdir / "population.list").write_text(POPULATION, encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
