#!/usr/bin/env python3
"""生成 diamond native 测试用的合成输入。

DIAMOND 比对需要真实数据库（建库 + 比对耗时），合成数据无法覆盖真实计算。因此本脚本生成
「最小蛋白/核酸 FASTA」，run_test.sh 以 **argv 构造断言**（monkeypatch 二进制解析）验证命令
构建不崩溃，不依赖已安装的 diamond。

产出：
  <outdir>/uniprot_sprot.fasta   蛋白库 FASTA（2 条）
  <outdir>/longest_orfs.pep      查询蛋白 FASTA（2 条）
  <outdir>/transcripts.fa        查询核酸 FASTA（blastx 用，2 条）
"""
from __future__ import annotations

import sys
from pathlib import Path

PROT = (
    ">sp|P00001|TEST1 test protein 1\n"
    "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
    ">sp|P00002|TEST2 test protein 2\n"
    "MALWMRLLPLLALLALWGPDPAAAFVNQHLCG\n"
)

NUCL = (
    ">TRINITY_DN_c1_g1_i1\n"
    "ATGAAAACCGCATACATTGCCAAACAACGCCAAATTAGCTTTGTGAAAAGCCATTTTAGCCGCCAACTGGAAGAACGCCTGGGCCTGATTGAAGTTCAA\n"
    ">TRINITY_DN_c2_g1_i1\n"
    "ATGGCCCTGTGGATGCGCCTCCTGCCCCTGCTGGCGCTGCTGGCCCTCTGGGGACCTGACCCAGCCGCAGCCTTTGTGAACCAACACCTGTGCGG\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "uniprot_sprot.fasta").write_text(PROT, encoding="utf-8")
    (outdir / "longest_orfs.pep").write_text(PROT, encoding="utf-8")
    (outdir / "transcripts.fa").write_text(NUCL, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
