#!/usr/bin/env python3
"""生成 cd-hit native 测试用的合成数据。

产出（<outdir> 下）：
  proteins.fa     5 条蛋白序列（3 条互为近重复 + 2 条另一家族的近重复）
  nucleotides.fa  3 条核酸序列（2 条互为近重复 + 1 条无关）

设计：在 -c 0.9（默认阈值）下，近重复序列应被聚为一簇、代表序列数应少于输入序列数，
便于 run_test.sh 断言「去冗余后 >input 条数减少」。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 蛋白 base（~160 aa）与其近重复
PROT_A = (
    "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEK"
    "AVQVKVKALPDAQFEVVHSLAKWKRPPQDFRGPLVVGQYAATLHSFMQEQGI"
    "SLDQLVEMVRKLEAEYPQIPVIGGHSYGGMVAQYLVKNGWTSPDAWDAA"
)
# 另一蛋白家族（GFP 样，与 PROT_A 无关）
PROT_D = (
    "MSKGEELFTGVVPILVELDGDVNGHKFSVSGEGEGDATYGKLTLKFICTTGKLPVPWPTLVTTF"
    "SYGVQCFSRYPDHMKRHDFFKSAMPEGYVQERTIFFKDDGNYKTRAEVKFEGDTLVNRIELKGI"
    "DFKEDGNILGHKLEYNYNSHNVYIMADKQKNGIKVNFKIRHNIEDGSVQLADHYQQNTPIGDGP"
    "VLLPDNHYLSTQSALSKDPNEKRDHMVLLEFVTAAGITHGMDELYK"
)

# 核酸 base（210 nt）与其近重复
NUCL_A = (
    "ATGGCTAGCAAAGGTGAAGAACTGTTCACCGGTGTGGTTCCAATCCTGGTTGAACTGGATGGTGAT"
    "GTTAACGGTCACAAATTCTCTGTGTCTGGTGAAGGTGAAGGTGATGCAACTTACGGTAAACTG"
    "ACCCTGAAATTCATCTGTACCACTGGTAAACTGCCAGTTCCTTGGCCAACTCTGGTTACCACT"
)
# 无关核酸（另一段组成差异较大的序列）
NUCL_C = (
    "TTGACGGATCCGTTACGCATGCGTTAAGCTAGGCATCGATTACGGCCTAGGCTAACGTTAGCAT"
    "GGCTACGTAGCTAGCTAGGCTTACGATCGTAGCTAGCATCGATCGATCGGCTAGCTAGCATCG"
    "ATCGTAGCTAGCTAGGCATCGTAGCTAGCATCGATTACGATCGATCGTAGCTAGCTAGCAT"
)


def mutate(seq: str, edits: tuple[tuple[int, str], ...]) -> str:
    """按 (位置, 新碱基/残基) 列表替换，得到近重复序列。"""
    lst = list(seq)
    for pos, new in edits:
        lst[pos] = new
    return "".join(lst)


def write_fasta(path: Path, records: list[tuple[str, str]], width: int = 60) -> None:
    with open(path, "w") as fh:
        for name, seq in records:
            fh.write(f">{name}\n")
            for i in range(0, len(seq), width):
                fh.write(seq[i:i + width] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    proteins = [
        ("prot_A", PROT_A),
        ("prot_B", mutate(PROT_A, ((10, "A"), (50, "G"), (90, "S")))),   # 与 A 近重复
        ("prot_C", mutate(PROT_A, ((20, "T"), (60, "A"), (120, "P")))),  # 与 A 近重复
        ("prot_D", PROT_D),
        ("prot_E", mutate(PROT_D, ((15, "K"), (80, "Q")))),              # 与 D 近重复
    ]
    nucleotides = [
        ("nucl_A", NUCL_A),
        ("nucl_B", mutate(NUCL_A, ((30, "G"), (90, "T"), (150, "C")))),  # 与 A 近重复
        ("nucl_C", NUCL_C),
    ]

    write_fasta(outdir / "proteins.fa", proteins)
    write_fasta(outdir / "nucleotides.fa", nucleotides)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
