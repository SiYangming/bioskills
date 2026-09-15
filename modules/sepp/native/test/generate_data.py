#!/usr/bin/env python3
"""生成 sepp native 测试用的合成输入。

SEPP 的真实放置需要参考树 + 比对 + 大量片段并调用 HMMER/RAxML，合成数据无法覆盖真实计算。
因此本脚本只生成「结构合法的最小文本输入」，run_test.sh 在 sepp 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/ref.tree             最小 Newick 参考树（3 taxa）
  <outdir>/ref_aln.fasta        参考比对（等长 FASTA）
  <outdir>/fragments.fasta      待放置片段（未比对 FASTA）
  <outdir>/ref.RAxML_info       RAxML_info 文本占位
  <outdir>/seqs.fasta           UPP 输入未比对序列
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

    # 最小 Newick 树（3 个叶）
    (outdir / "ref.tree").write_text("((A:0.1,B:0.1):0.1,C:0.2);\n", encoding="utf-8")

    # 参考比对（3 条等长序列）
    (outdir / "ref_aln.fasta").write_text(
        ">A\nACGTACGTAC\n"
        ">B\nACGTACGTAC\n"
        ">C\nACGTACGTAC\n",
        encoding="utf-8",
    )

    # 待放置片段（比参考短的未比对序列）
    (outdir / "fragments.fasta").write_text(
        ">q1\nACGTAC\n"
        ">q2\nGTACGT\n",
        encoding="utf-8",
    )

    # RAxML_info 文本占位（真实运行需 RAxML 生成的模型参数）
    (outdir / "ref.RAxML_info").write_text(
        "# PLACEHOLDER: RAxML_info（真实放置需 RAxML 生成；此处仅供 argv 构造测试）\n"
        "Model: GTRGAMMA\n",
        encoding="utf-8",
    )

    # UPP 输入
    (outdir / "seqs.fasta").write_text(
        ">s1\nACGTACGTAC\n"
        ">s2\nACGTACGTAC\n"
        ">s3\nACGTACGTAC\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
