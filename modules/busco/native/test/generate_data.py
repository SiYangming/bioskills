#!/usr/bin/env python3
"""生成 busco native 测试用的合成输入。

BUSCO 真实运行需要谱系数据库（OrthoDB odb10，数百 MB，需另行下载），合成数据无法覆盖真实评估。
因此本脚本生成「最小 FASTA + config ini 占位」，run_test.sh 在 BUSCO 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/genome.fasta     最小基因组（run -m genome）
  <outdir>/proteins.fasta   最小蛋白序列（run -m proteins）
  <outdir>/config.ini       最小 config 占位（config 子命令输入）
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

    (outdir / "genome.fasta").write_text(
        ">scaffold1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8"
    )
    (outdir / "proteins.fasta").write_text(
        ">prot1\nMAKLTESTPEPTIDE\n", encoding="utf-8"
    )
    (outdir / "config.ini").write_text(
        "[busco_run]\n"
        "lineage = basidiomycota_odb10\n"
        "offline = True\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
