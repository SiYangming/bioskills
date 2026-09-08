#!/usr/bin/env python3
"""生成 humann native 测试用的合成输入。

HUMAnN 主流程（run）需要联网下载 ChocoPhlAn / UniRef / MetaPhlAn 数据库，合成数据
无法覆盖真实计算；因此本脚本生成「文本占位 + 说明」，run_test.sh 退化为「用 python
构造 argv 验证命令构建不崩溃」的断言方式（同 dorado/stringtie 模块约定），并在本机
已安装 humann 时额外做 --version 冒烟。

产出：
  <outdir>/reads.fastq            最小 FASTQ 占位（run 输入）
  <outdir>/sample1_genefamilies.tsv  最小丰度表占位（renorm / join / regroup 输入）
  <outdir>/sample2_genefamilies.tsv  最小丰度表占位（join 多文件）
"""
from __future__ import annotations

import sys
from pathlib import Path

FASTQ = (
    "@read1\n"
    "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
    "+\n"
    "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"
)

GENEFAMILIES = (
    "# Gene Family\tSample\n"
    "UNMAPPED\t50.0\n"
    "UNINTEGRATED\t20.0\n"
    "UniRef90_unknown\t30.0\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "reads.fastq").write_text(FASTQ, encoding="utf-8")
    (outdir / "sample1_genefamilies.tsv").write_text(GENEFAMILIES, encoding="utf-8")
    (outdir / "sample2_genefamilies.tsv").write_text(GENEFAMILIES, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
