#!/usr/bin/env python3
"""生成 biom-format native 测试用的合成输入。

BIOM 是二进制/JSON 特征表格式，合成一份「经典 OTU 表（classic TSV）」即可在 biom 可用时
真实转换/统计；biom 未安装时 run_test.sh 退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出（<outdir> 下）：
  classic_table.tsv   经典 OTU 表（首行注释 + #OTU ID 表头 + taxonomy 列），biom 可读
  feature-table.biom  文本占位（仅用于 argv 构造断言，非真实 BIOM 文件）
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

    (outdir / "classic_table.tsv").write_text(
        "# Constructed from biom file\n"
        "#OTU ID\tsample1\tsample2\ttaxonomy\n"
        "OTU1\t1\t2\tk__Bacteria;\n"
        "OTU2\t3\t4\tk__Bacteria; p__Firmicutes;\n"
        "OTU3\t5\t0\tk__Bacteria; p__Proteobacteria;\n",
        encoding="utf-8",
    )
    (outdir / "feature-table.biom").write_text(
        "# PLACEHOLDER: 真实 BIOM 文件由 biom convert 生成\n", encoding="utf-8"
    )
    print(f"已生成 biom-format 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
