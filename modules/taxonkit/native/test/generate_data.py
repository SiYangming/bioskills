#!/usr/bin/env python3
"""生成 taxonkit native 测试用的合成输入。

taxonkit 的真实运行依赖完整 NCBI Taxonomy 数据库（~/.taxonkit 下 nodes.dmp/names.dmp 等，
约数百 MB），合成数据无法覆盖真实查询。因此本脚本生成「文本输入 + 说明」，run_test.sh
在 taxonkit 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/taxids.txt         TaxID 列表（lineage 输入；含真菌界 4751）
  <outdir>/names.txt          物种名列表（name2taxid 输入）
  <outdir>/lineage.tsv        lineage 结果占位（reformat 输入）
  <outdir>/sub.fungi.list     list 输出占位（提取真菌子集示例）
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

    (outdir / "taxids.txt").write_text("4751\n2\n10239\n", encoding="utf-8")
    (outdir / "names.txt").write_text(
        "Malassezia sympodialis\nSaccharomyces cerevisiae\n", encoding="utf-8"
    )
    # lineage 输出占位（TaxID<TAB>lineage<TAB>rank），供 reformat 输入
    (outdir / "lineage.tsv").write_text(
        "4751\tcellular organisms;Eukaryota;Opisthokonta;Fungi\tno rank\n",
        encoding="utf-8",
    )
    (outdir / "sub.fungi.list").write_text(
        "# PLACEHOLDER: taxonkit list --ids 4751 输出（每行一个 TaxID）\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
