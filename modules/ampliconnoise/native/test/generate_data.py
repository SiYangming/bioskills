#!/usr/bin/env python3
"""生成 ampliconnoise native 测试用的合成输入（保持仓库轻量，不提交真实测序数据）。

AmpliconNoise 真实运行需 454 SFF / fasta+qual 与 MPI，合成数据无法覆盖真实计算；本脚本只
生成最小占位输入与 Data/ 资源占位，run_test.sh 退化为「argv 构造验证 + stub 程序 CLI 冒烟」。

产出（<outdir> 下）：
  reads.fna        占位 reads FASTA
  reads.qual       占位质量文件
  reads.sff        SFF 占位（PyroNoise -s 输入占位）
  Data/LookUp.dat  资源占位（对照真实发布包 Data/ 资源）
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

    (outdir / "reads.fna").write_text(
        ">read1\nACGTACGTACGTACGTACGT\n>read2\nACGTACGTACGTACGTACGA\n",
        encoding="utf-8",
    )
    (outdir / "reads.qual").write_text(
        ">read1\n40 40 40 40 40 40 40 40 40 40 40 40 40 40 40 40 40 40 40 40\n",
        encoding="utf-8",
    )
    (outdir / "reads.sff").write_text("# PLACEHOLDER SFF（占位，非真实 454 数据）\n", encoding="utf-8")
    (outdir / "Data").mkdir(exist_ok=True)
    (outdir / "Data" / "LookUp.dat").write_text("# PLACEHOLDER LookUp.dat\n", encoding="utf-8")
    print(f"已生成 ampliconnoise 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
