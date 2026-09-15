#!/usr/bin/env python3
"""生成 metaeuk native 测试用的合成输入。

MetaEuk 真实运行需要 MMseqs2 建库 + 同源搜索 + 动态规划外显子恢复，合成数据无法覆盖真实计算。
因此本脚本生成「最小 FASTA / TSV 占位」，run_test.sh 在 metaeuk 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/contigs.fna       最小 contig（easy_predict 输入）
  <outdir>/proteins.faa      最小参考蛋白（easy_predict 输入）
  <outdir>/query.faa         查询序列（easy_search 输入）
  <outdir>/target.faa        目标序列（easy_search 输入）
  <outdir>/headersMap.tsv    预测-标识映射占位（taxtocontig 输入）
  <outdir>/contigsDB         contig 库占位（taxtocontig 输入）
  <outdir>/seqTaxDb.tsv      带分类蛋白库占位（taxtocontig 输入）
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

    (outdir / "contigs.fna").write_text(
        ">contig1\nATGAAACTGACGGTGAAAGCGTTTTAA\n", encoding="utf-8"
    )
    (outdir / "proteins.faa").write_text(
        ">target1\nMKLTVKAF\n", encoding="utf-8"
    )
    (outdir / "query.faa").write_text(
        ">q1\nMKLTVKAF\n", encoding="utf-8"
    )
    (outdir / "target.faa").write_text(
        ">t1\nMKLTVKAF\n", encoding="utf-8"
    )
    (outdir / "headersMap.tsv").write_text(
        "pred1\tcontig1\n", encoding="utf-8"
    )
    (outdir / "contigsDB").write_text(
        "# PLACEHOLDER: MMseqs2/metaeuk createdb contig database\n", encoding="utf-8"
    )
    (outdir / "seqTaxDb.tsv").write_text(
        "# PLACEHOLDER: taxonomy-annotated protein database\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
