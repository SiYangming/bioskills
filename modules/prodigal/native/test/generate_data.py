#!/usr/bin/env python3
"""生成 prodigal native 测试用的合成输入。

Prodigal 真实预测需要有一定长度的原核基因组（过短会告警/拒绝），合成数据无法覆盖真实生物学计算。
因此本脚本生成「一段约 30 kb 的合成序列（含周期性 ORF 样结构）」，run_test.sh 在 prodigal 未安装时
退化为「用 python 构造 argv 验证命令构建不崩溃」；已安装时对合成序列做一次真实预测冒烟。

产出：
  <outdir>/genome.fna       约 30 kb 合成基因组（FASTA，ACGT）
  <outdir>/contigs.fna      较小 contig 集（meta 模式占位）
"""
from __future__ import annotations

import random
import sys
from pathlib import Path


def synth_genome(length: int = 30000, seed: int = 7) -> str:
    """生成一段确定性的合成序列：以 ATG 起始、TAA/TAG/TGA 终止的 ORF 样周期拼接。"""
    rnd = random.Random(seed)
    orfs = []
    while sum(len(o) for o in orfs) < length:
        # 起始 ATG + 若干密码子 + 终止子
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
    # 按 70 列换行输出 FASTA
    lines = [genome[i:i + 70] for i in range(0, len(genome), 70)]
    (outdir / "genome.fna").write_text(
        ">synthetic_ecoli_like\n" + "\n".join(lines) + "\n", encoding="utf-8"
    )
    # 较小的 contig 集（meta 模式占位）
    (outdir / "contigs.fna").write_text(
        ">contig1\n" + "\n".join(lines) + "\n", encoding="utf-8"
    )
    print(f"已生成测试合成基因组（{len(genome)} bp）-> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
