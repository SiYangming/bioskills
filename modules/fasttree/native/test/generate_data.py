#!/usr/bin/env python3
"""生成 fasttree native 测试用的合成输入。

FastTree 建树需要可比对的序列；本脚本生成「结构合法的小蛋白/核酸比对」占位，既能做
run_test.sh 的 argv 构造断言，也能在 FastTree 已安装时做一次真实的极小规模建树冒烟。

产出：
  <outdir>/aln.prot.fasta  6 条约 60 aa 的蛋白比对
  <outdir>/aln.nucl.fasta  6 条约 90 nt 的核酸比对（对应上述蛋白的简化编码）
"""
from __future__ import annotations

import sys
from pathlib import Path

_PROT = {
    "sp1": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLLNNNN",
    "sp2": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLLNNNN",
    "sp3": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLMNNNN",
    "sp4": "MKTIIALTYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLADDDD",
    "sp5": "MKTIIALTYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLADDDD",
    "sp6": "MRTIIALTYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLADDDD",
}

# 核酸：每个氨基酸用 3 nt 的简化映射生成可比较的 DNA 序列
_CODON = {
    "M": "ATG", "K": "AAA", "T": "ACC", "I": "ATT", "A": "GCT", "L": "CTG",
    "S": "TCT", "Y": "TAT", "F": "TTT", "C": "TGT", "V": "GTT", "D": "GAT",
    "R": "CGT", "G": "GGT", "H": "CAT", "E": "GAA", "N": "AAT", "W": "TGG",
    "Q": "CAA", "P": "CCT",
}


def _to_dna(seq: str) -> str:
    return "".join(_CODON.get(aa, "NNN") for aa in seq)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "aln.prot.fasta").write_text(
        "".join(f">{name}\n{seq}\n" for name, seq in _PROT.items()), encoding="utf-8"
    )
    (outdir / "aln.nucl.fasta").write_text(
        "".join(f">{name}\n{_to_dna(seq)}\n" for name, seq in _PROT.items()), encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
