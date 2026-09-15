#!/usr/bin/env python3
"""生成 prothint native 测试用的合成输入。

ProtHint 的真实运行需要参考蛋白库 + DIAMOND/Spaln 比对，合成数据无法覆盖真实计算。
因此本脚本生成「最小 FASTA + GFF 占位」，run_test.sh 在 ProtHint 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/genome.fasta     最小基因组（predict 输入）
  <outdir>/proteins.fasta   最小参考蛋白（predict 输入）
  <outdir>/prothint.gff     最小 hints GFF（high_confidence 输入占位）
  <outdir>/evidence.gff     高置信子集占位（augustus_hints 输入）
  <outdir>/chains.gff       蛋白链占位（augustus_hints 输入）
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
        ">contig1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n", encoding="utf-8"
    )
    (outdir / "proteins.fasta").write_text(
        ">prot1\nMAKLTESTPEPTIDE\n", encoding="utf-8"
    )
    # 最小 hints GFF：一行 intron，high_confidence/augustus_hints 只做输入占位
    (outdir / "prothint.gff").write_text(
        "##gff-version 3\n"
        "contig1\tProtHint\tintron\t6\t12\t.\t+\t.\tmult=1;src=P\n",
        encoding="utf-8",
    )
    (outdir / "evidence.gff").write_text(
        "##gff-version 3\n"
        "contig1\tProtHint\tintron\t6\t12\t.\t+\t.\tmult=1;src=M;pri=4\n",
        encoding="utf-8",
    )
    (outdir / "chains.gff").write_text(
        "##gff-version 3\n"
        "contig1\tProtHint\tchain\t1\t18\t.\t+\t.\tprot1\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
