#!/usr/bin/env python3
"""生成 interproscan native 测试用的合成输入。

真实注释依赖 InterProScan 发行包的分析数据（Pfam/HMMER 等，数十 GB），合成数据无法覆盖真实计算，
因此本脚本生成「最小蛋白 FASTA」，run_test.sh 在未安装 interproscan.sh 时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/proteins.fasta   最小蛋白 FASTA（run 输入）
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

    (outdir / "proteins.fasta").write_text(
        ">g1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">g2\nMSTAGKVIKCKAAVLWELKKPFSIEEVEVAPPK\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
