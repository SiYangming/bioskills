#!/usr/bin/env python3
"""生成 orthomcl native（说明型驱动）测试用的合成输入。

OrthoMCL 流程依赖 MySQL，本模块为「说明型 + 命令构造」（不实际运行），因此测试只用
python 构造 argv 验证命令构建（monkeypatch 脚本解析）。本脚本生成结构正确的占位输入。

产出：
  <outdir>/proteome.fasta        最小蛋白 FASTA（adjust_fasta 输入）
  <outdir>/blast.out             最小 BLAST/DIAMOND outfmt6 表格（blast_parser 输入）
  <outdir>/similarSequences.txt  占位相似序列对（load_blast 输入）
  <outdir>/orthomcl.config       占位配置（MySQL 连接/schema）
  <outdir>/compliantFasta/       空目录（filter_fasta / blast_parser 的 compliantFasta）
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

    (outdir / "proteome.fasta").write_text(
        ">gene0001 hypothetical protein\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">gene0002 hypothetical protein\nMSTAGKVIKCKAAVLWEEKKPFSIEEVEVAPPK\n",
        encoding="utf-8",
    )
    (outdir / "blast.out").write_text(
        "gene0001\tgene0002\t95.5\t40\t1\t0\t1\t40\t1\t40\t1e-30\t120\n",
        encoding="utf-8",
    )
    (outdir / "similarSequences.txt").write_text(
        "gene0001\tgene0002\tspeciesA\tspeciesB\t1e-30\t30\t95.5\t40\n",
        encoding="utf-8",
    )
    (outdir / "orthomcl.config").write_text(
        "# OrthoMCL 配置占位（MySQL 连接信息）\n"
        "dbVendor=mysql\n"
        "dbConnectString=dbi:mysql:orthomcl:localhost:3306\n"
        "dbLogin=orthomcl\n"
        "dbPassword=CHANGE_ME\n",
        encoding="utf-8",
    )
    (outdir / "compliantFasta").mkdir(exist_ok=True)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
