#!/usr/bin/env python3
"""生成 trf（Tandem Repeats Finder）native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fa   单条序列的小基因组（约 200 bp），内含两段串联重复：
              - period=7 的 "ACGTACG" × 8
              - period=7 的 "GGATTCC" × 9
              两侧为无重复侧翼，确保 trf 在默认参数（2 7 7 80 10 50 500）下能命中。

说明：trf 的产物文件名以「输入文件 + 7 个参数值」为前缀并写在输入文件同目录，
故测试时把 FASTA 放进临时工作目录即可。
"""
from __future__ import annotations

import sys
from pathlib import Path

FLANK5 = "TTGACCGATCAGTTACCGGAATCCAGTT"          # 28 bp 无重复侧翼
UNIT_A = "ACGTACG" * 8                            # period=7 重复，56 bp
MIDDLE = "GGATCCTTAGGC"                           # 12 bp 间隔
UNIT_B = "GGATTCC" * 9                            # period=7 重复，63 bp
FLANK3 = "AACCGGTTACGATCGATTACGGCAT"              # 25 bp 无重复侧翼

SEQ = FLANK5 + UNIT_A + MIDDLE + UNIT_B + FLANK3


def write_fasta(path: Path) -> None:
    with open(path, "w") as fh:
        fh.write(">chr1 test contig with tandem repeats\n")
        for i in range(0, len(SEQ), 60):
            fh.write(SEQ[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "genome.fa")
    print(f"已生成测试数据 -> {outdir / 'genome.fa'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
