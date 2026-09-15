#!/usr/bin/env python3
"""生成 IGV native 测试用的合成输入。

IGV 是 Java 图形界面工具，无法在无显示环境完成真实可视化，因此本脚本只生成
「最小占位输入」，run_test.sh 在 igv 未安装时退化为「用 python 构造 argv 验证
命令构建不崩溃」。

产出：
  <outdir>/hg18.genome   最小 .genome 占位（IGV 基因组文件，key=value 文本）
  <outdir>/sample.bed    最小 BED 轨道占位
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

    (outdir / "hg18.genome").write_text(
        "id=hg18_test\n"
        "name=Synthetic test genome\n"
        "fasta=hg18.fa\n"
        "chromAlias=hg18.chrom.sizes\n",
        encoding="utf-8",
    )
    (outdir / "sample.bed").write_text(
        "scaffold_1\t0\t30\tfeature1\t0\t+\n",
        encoding="utf-8",
    )
    print(f"已生成 IGV 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
