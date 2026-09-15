#!/usr/bin/env python3
"""生成 table2asn native 测试用的合成输入。

table2asn 需要真实 FASTA + Feature Table(.tbl) + 提交模板(.sbt) 才能产出 .sqn，
合成数据无法覆盖真实转换。因此本脚本只生成「最小占位文件」，run_test.sh 在
table2asn 未安装时走「stub 二进制 + argv 构造验证」路径（不实际转换）。

产出：
  <outdir>/ecoli.fsa   最小 FASTA 序列（defline 含 organism/topology，与 .tbl/.sbt 同名）
  <outdir>/ecoli.sbt   最小提交模板占位（Submit-block 结构占位，非可直接提交的模板）
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

    (outdir / "ecoli.fsa").write_text(
        ">contig00001 [organism=Escherichia coli] [topology=linear]\n"
        "ATGCGTACGTAGCTAGCTAGCTAGCATCGATCGATCGTAGCTAGCTA\n",
        encoding="utf-8",
    )
    (outdir / "ecoli.sbt").write_text(
        "Submit-block ::= {\n"
        "  contact {\n"
        "    name name { last \"Doe\", first \"Jane\" },\n"
        "  },\n"
        "  cite { },\n"
        "}\n",
        encoding="utf-8",
    )
    print(f"已生成 table2asn 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
