#!/usr/bin/env python3
"""生成 stringtie native 测试用的合成输入。

stringtie assemble 需要真实比对 BAM 才能重构转录本，合成数据无法覆盖真实计算。
因此本脚本生成「文本占位 + 说明」，run_test.sh 在 stringtie 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃 + 纯文本 fix_gtf 真实执行」。

产出：
  <outdir>/sample.sorted.bam   文本占位（assemble 输入）
  <outdir>/sample.gtf          最小 GTF（含一处坐标颠倒，供 fix_gtf 真实回归）
  <outdir>/gtf_list.txt        GTF 列表（merge 输入）
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

    (outdir / "sample.sorted.bam").write_text(
        "# PLACEHOLDER: stringtie assemble 需要真实 long-read sorted BAM\n", encoding="utf-8"
    )
    # 最小 GTF：第二行故意坐标颠倒（start 200 > end 100），fix_gtf 应修复为 100/200
    (outdir / "sample.gtf").write_text(
        "# test gtf\n"
        "chr1\ttest\texon\t100\t150\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";\n"
        "chr1\ttest\texon\t200\t100\t.\t+\t.\tgene_id \"g2\"; transcript_id \"t2\";\n",
        encoding="utf-8",
    )
    (outdir / "gtf_list.txt").write_text(
        f"{outdir / 'sample.gtf'}\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
