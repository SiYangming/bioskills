#!/usr/bin/env python3
"""genetribe 测试数据生成（保持仓库轻量：只生成极小占位输入，不跑真实 blastp/MCScan）。

GeneTribe core 需要真实基因组蛋白集 + 注释 + BLAST/MCScan 才能实际运行；合成数据无法覆盖
真实共线性搜索计算。因此本脚本只生成两个「物种」的占位输入（.fa / .bed / .chrlist /
.genelength / .confidence / 预计算 .blast 片段），供 run_test.sh 的 argv 构造断言与文档示例引用。
"""

from __future__ import annotations

import sys
from pathlib import Path


def main(outdir: str) -> None:
    work = Path(outdir)
    work.mkdir(parents=True, exist_ok=True)

    # 极小演示蛋白 FASTA（aet/rice 各 2 条，仅用于命令构造/占位演示，不可当真库使用）
    (work / "aet.fa").write_text(
        ">AET1Gv20000010.1 pep chromosome:AET1:1:1000:2000:-1 gene:AET1Gv20000010 transcript:AET1Gv20000010.1\n"
        "MKLFKLSLLLALPLAAAVLADDTCCSVDADHAVPTTVGVKPR\n"
        ">AET1Gv20000020.1 pep chromosome:AET1:1:3000:5000:+1 gene:AET1Gv20000020 transcript:AET1Gv20000020.1\n"
        "MGRQKQPKRKPKKGQKVPKKKPRRKKKAPAAQKPAPKA\n",
        encoding="ascii",
    )
    (work / "rice.fa").write_text(
        ">Os01g0100100.1 pep chromosome:1:2000:3000:+1 gene:Os01g0100100 transcript:Os01g0100100.1\n"
        "MKLFKLSLLLALPLAAAVLADDTCCSVDADHAVPTTVGVKPR\n"
        ">Os01g0100200.1 pep chromosome:1:4000:6000:-1 gene:Os01g0100200 transcript:Os01g0100200.1\n"
        "MGRQKQPKRKPKKGQKVPKKKPRRKKKAPAAQKPAPKA\n",
        encoding="ascii",
    )

    # 六列 gene bed（chr start end id score strand）
    (work / "aet.bed").write_text(
        "chr1A\t1000\t2000\tAET1Gv20000010\t0\t-\n"
        "chr1A\t3000\t5000\tAET1Gv20000020\t0\t+\n",
        encoding="ascii",
    )
    (work / "rice.bed").write_text(
        "1\t2000\t3000\tOs01g0100100\t0\t+\n"
        "1\t4000\t6000\tOs01g0100200\t0\t-\n",
        encoding="ascii",
    )

    # 染色体组信息（chrlist；亚基因组特征串须可被子 bed 第 1 列包含）
    (work / "aet.chrlist").write_text("chrNA,chrNB,chrND\n", encoding="ascii")
    (work / "rice.chrlist").write_text("N\n", encoding="ascii")

    # sameassembly 用基因长度表（bed 第 4 列 + 长度）
    (work / "aet.genelength").write_text(
        "AET1Gv20000010\t1000\nAET1Gv20000020\t2000\n", encoding="ascii"
    )
    (work / "rice.genelength").write_text(
        "Os01g0100100\t1000\nOs01g0100200\t2000\n", encoding="ascii"
    )

    # core -c 置信度文件（可选）
    (work / "aet.confidence").write_text(
        "AET1Gv20000010\tHC\nAET1Gv20000020\tHC\n", encoding="ascii"
    )

    # 预计算 BLAST 片段（outfmt6 头 3 列仅作占位；实际 blast 表无表头）
    (work / "aet_rice.blast").write_text(
        "AET1Gv20000010\tOs01g0100100\t100.0\n", encoding="ascii"
    )
    (work / "rice_aet.blast").write_text(
        "Os01g0100100\tAET1Gv20000010\t100.0\n", encoding="ascii"
    )

    # RBH/CBS/longestcds 工具输入占位
    (work / "A_vs_B.score").write_text("A1\tB1\t100\nA1\tB2\t200\n", encoding="ascii")
    (work / "B_vs_A.score").write_text("B1\tA1\t200\nB2\tA1\t300\n", encoding="ascii")
    (work / "aet.rice.lifted.anchors").write_text(
        "## Alignment 1: score=100\nAET1Gv20000010\tOs01g0100100\n", encoding="ascii"
    )

    print(f"[generate_data] wrote placeholder inputs to {work}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: generate_data.py <outdir>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1])
