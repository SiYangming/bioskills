#!/usr/bin/env python3
"""dia-nn 测试数据生成（保持仓库轻量：不提交 .raw / 模型等大文件）。

DIA-NN 需要真实质谱原始数据（Thermo .raw / Bruker .d / .mzML）才能实际运行，
合成数据无法覆盖真实搜索计算；因此本脚本只生成一个极小的演示 FASTA
（蛋白库占位）+ 标记目录，供 run_test.sh 的 argv 构造断言与文档示例引用。
"""

from __future__ import annotations

import sys
from pathlib import Path


def main(outdir: str) -> None:
    work = Path(outdir)
    work.mkdir(parents=True, exist_ok=True)

    # 极小演示蛋白库（2 条 + 常见污染物），仅用于命令构造/占位演示，不可当真库使用
    fasta = work / "mini_proteome.fasta"
    fasta.write_text(
        ">sp|P0A7B0|demo_protein_1 (synthetic demo entry)\n"
        "MKLFKLSLLLALPLAAAVLADDTCCSVDADHAVPTTVGVKPR\n"
        ">sp|P0A7B1|demo_protein_2 (synthetic demo entry)\n"
        "MGRQKQPKRKPKKGQKVPKKKPRRKKKAPAAQKPAPKA\n"
        ">sp|P02769|ALBU_BOVIN Serum albumin (real entry, brief)\n"
        "MKWVTFISLLFLFSSAYSRGVFRRDTHKSEIAHRFKDLGEEHFKGLVLIAFSQYLQ\n",
        encoding="ascii",
    )

    # 模拟原始数据目录占位（真实 .raw 无法合成；文档示例指向此处）
    rawdir = work / "raw"
    rawdir.mkdir(exist_ok=True)
    (rawdir / "README.txt").write_text(
        "Placeholder: put real .raw/.d/.mzML files here for a real diann run.\n",
        encoding="ascii",
    )

    print(f"[generate_data] wrote {fasta} and {rawdir}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: generate_data.py <outdir>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1])
