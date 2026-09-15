#!/usr/bin/env python3
"""生成 eggnog-mapper native 测试用的合成输入。

真实注释依赖 emapperdb-4.5.1（HMM/DIAMOND 数据库，数十 GB），合成数据无法覆盖真实搜索，
因此本脚本生成「最小蛋白 FASTA + 命中表占位」，run_test.sh 在未安装 emapper.py 时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/proteins.fasta         最小蛋白 FASTA（annotate 输入）
  <outdir>/hits.tsv               同源命中表占位（annotate_hits 输入）
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
    (outdir / "hits.tsv").write_text(
        "g1\t100\t0.0\t1e-50\t60.0\n"
        "g2\t200\t0.0\t1e-40\t50.0\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
