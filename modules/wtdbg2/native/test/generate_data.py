#!/usr/bin/env python3
"""生成 wtdbg2 native 测试用的合成输入。

wtdbg2 建图/一致性需要真实长读数据（且数据量较大），合成数据无法覆盖真实计算。因此本脚本生成
「可解析的占位长读 FASTA + 布局文件占位 + 说明」，run_test.sh 在二进制未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/subreads.fasta    合成长读序列（数条，仅用于 argv 构造验证）
  <outdir>/dbg.ctg.lay.gz    文本占位（模拟 wtdbg2 建图产物，作为 cns 输入）
  <outdir>/dbg.raw.fa        草图序列占位（作为 polish 输入）
  <outdir>/dbg.bam           比对结果占位（文本，作为 polish 输入）
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

    seq = "ACGT" * 250  # 1000 bp 占位长读
    with open(outdir / "subreads.fasta", "w", encoding="utf-8") as fh:
        for i in range(1, 4):
            fh.write(f">read_{i}\n{seq}\n")
    (outdir / "dbg.ctg.lay.gz").write_text(
        "# PLACEHOLDER: wtdbg2 建图产物 <prefix>.ctg.lay.gz\n", encoding="utf-8")
    (outdir / "dbg.raw.fa").write_text(
        "# PLACEHOLDER: wtpoa-cns 一致性产出的草图 FASTA\n>ctg1\n" + seq + "\n",
        encoding="utf-8")
    (outdir / "dbg.bam").write_text(
        "# PLACEHOLDER: minimap2/samtools 产出的 BAM（polish 输入）\n", encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
