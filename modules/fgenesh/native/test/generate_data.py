#!/usr/bin/env python3
"""生成 fgenesh native 测试用的合成输入。

FGENESH 需要真实基因组 + Softberry 授权参数文件（*.par）才能预测；且软件许可受限、本机通常
未安装，故本脚本仅生成占位数据，run_test.sh 做「argv 构造验证」而不做真实预测。

产出：
  <outdir>/genome.fa          最小基因组序列（FASTA）
  <outdir>/params/fungi.par   物种参数文件占位（真实文件由 Softberry 授权发行包提供）
"""
from __future__ import annotations

import sys
from pathlib import Path

_GENOME = ">contig_test\n" + ("ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n" * 4)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    (outdir / "params").mkdir(parents=True, exist_ok=True)

    (outdir / "genome.fa").write_text(_GENOME, encoding="utf-8")
    (outdir / "params" / "fungi.par").write_text(
        "# FGENESH 参数文件占位（真实文件由 Softberry 授权发行包提供）\n",
        encoding="utf-8",
    )
    print(f"已生成 fgenesh 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
