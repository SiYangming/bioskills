#!/usr/bin/env python3
"""生成 go_class native 测试用的合成输入（最小文本占位，保持仓库轻量）。

产出：
  <outdir>/go.obo      最小 GO 本体（3 个顶层 namespace 术语）
  <outdir>/go.annot    最小 GO 注释（gene -> GO term TSV）
  <outdir>/go.wego     最小 WEGO 格式占位
  <outdir>/out.lst     go_svg.pl 清单占位
  <outdir>/out.svg     最小 SVG 占位
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

GO_ANNOT = "gene1\tGO:0008150\ngene2\tGO:0003674\ngene3\tGO:0005575\n"

GO_WEGO = "gene1\tGO:0008150\ngene2\tGO:0003674\ngene3\tGO:0005575\n"

OUT_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"></svg>\n'


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "go.obo").write_text(GO_OBO, encoding="utf-8")
    (outdir / "go.annot").write_text(GO_ANNOT, encoding="utf-8")
    (outdir / "go.wego").write_text(GO_WEGO, encoding="utf-8")
    (outdir / "out.lst").write_text("# placeholder out.lst\n", encoding="utf-8")
    (outdir / "out.svg").write_text(OUT_SVG, encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
