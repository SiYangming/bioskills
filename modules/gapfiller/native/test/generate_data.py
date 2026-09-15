#!/usr/bin/env python3
"""生成 gapfiller native 测试用的合成输入。

GapFiller.pl fill 需要真实双端 reads 与比对器（bowtie/bwa）才能做补洞，合成数据无法覆盖真实计算。
因此本脚本生成「可构造 argv 的占位输入」，run_test.sh 在 GapFiller.pl 未安装时退化为
「--list-commands/--schema 自省 + python 层 argv 构造断言（monkeypatch _resolve_binary）」。

产出：
  <outdir>/genome.fa        含 gap（N）的 scaffold FASTA
  <outdir>/fragment.1.fastq 双端 R1（4 条）
  <outdir>/fragment.2.fastq 双端 R2（4 条）
  <outdir>/library.txt      文库表（Lib1 bowtie fragment.1.fastq fragment.2.fastq 177 0.43 FR）
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

    (outdir / "genome.fa").write_text(
        ">scaffold1\n"
        "ACGTACGTACGTACGTACGTNNNNNNNNNNACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n"
        ">scaffold2\n"
        "TTTTGGGGCCCCAAAANNNNNNTTTTGGGGCCCCAAAATTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA\n",
        encoding="utf-8",
    )
    reads = [
        ("frag1/1", "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"),
        ("frag2/1", "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA"),
        ("frag3/1", "GGGGAAAACCCCAAAAGGGGAAAACCCCAAAAGGGGAAAACCCCAAAA"),
        ("frag4/1", "TTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGGTTTTCCCCAAAAGGGG"),
    ]
    for fn in ("fragment.1.fastq", "fragment.2.fastq"):
        with open(outdir / fn, "w", encoding="utf-8") as fh:
            for name, seq in reads:
                fh.write(f"@{name}\n{seq}\n+\n{'I' * len(seq)}\n")

    (outdir / "library.txt").write_text(
        "Lib1 bowtie fragment.1.fastq fragment.2.fastq 177 0.43 FR\n", encoding="utf-8"
    )
    print(f"已生成 gapfiller 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
