#!/usr/bin/env python3
"""生成 genemarks native 测试用的合成输入。

GeneMarkS/GeneMarkS-2 真实预测需一定长度的原核基因组，且运行需要已申请的密钥（~/.gmhmmp2_key）。
合成数据无法覆盖真实计算，因此本脚本生成「一段约 30 kb 的合成原核序列」，run_test.sh 在脚本未安装时
退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/genome.fasta   约 30 kb 合成基因组（FASTA，ACGT）
  <outdir>/gm_key_note    密钥申请/放置说明（占位，不包含真实密钥）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path


def synth_genome(length: int = 30000, seed: int = 11) -> str:
    rnd = random.Random(seed)
    orfs = []
    while sum(len(o) for o in orfs) < length:
        codons = ["ATG"]
        codons += ["".join(rnd.choice("ACGT") for _ in range(3)) for _ in range(rnd.randint(30, 90))]
        codons.append(rnd.choice(["TAA", "TAG", "TGA"]))
        orfs.append("".join(codons))
    return "".join(orfs)[:length]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    genome = synth_genome()
    lines = [genome[i:i + 70] for i in range(0, len(genome), 70)]
    (outdir / "genome.fasta").write_text(
        ">synthetic_prokaryote\n" + "\n".join(lines) + "\n", encoding="utf-8"
    )
    (outdir / "gm_key_note").write_text(
        "# 密钥申请（测试占位，不含真实密钥）\n"
        "# 官方：https://exon.gatech.edu/GeneMark/license_download.cgi\n"
        "# GeneMarkS-2：放置 ~/.gmhmmp2_key；旧版 GeneMarkS：放置 ~/.gm_key\n",
        encoding="utf-8",
    )
    print(f"已生成测试合成基因组（{len(genome)} bp）-> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
