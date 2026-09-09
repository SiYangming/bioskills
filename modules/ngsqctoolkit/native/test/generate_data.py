#!/usr/bin/env python3
"""生成 ngsqctoolkit native 测试用合成 FASTQ 与最小 toolkit 脚本骨架。

NGSQCToolkit 为 Perl 脚本集、无独立二进制；本模块测试契约是「argv 构造 +
自省」，不做真实 perl 回归（软件已淘汰）。因此本脚本产出：

  <outdir>/r1.fq, <outdir>/r2.fq         PE 双端合成 FASTQ（Phred+33 外观）
  <outdir>/single.fq                     SE 合成 FASTQ
  <outdir>/fake-toolkit/QC/IlluQC_PRLL.pl
  <outdir>/fake-toolkit/Trimming/TrimmingReads.pl
  <outdir>/fake-toolkit/Trimming/AmbiguityFiltering.pl

fake-toolkit 只是让 main.py 的 _script() 存在性检查通过的占位骨架（内容为空
perl 程序即可），argv 构造断言在 run_test.sh 中完成。
"""
from __future__ import annotations

import sys
from pathlib import Path


def write_fastq(path: Path, records: list[tuple[str, str, str]]) -> None:
    """(name, seq, qual_phred33) -> FASTQ；qual 为 Phred+33 字符。"""
    with open(path, "w") as fh:
        for name, seq, qual in records:
            fh.write(f"@{name}\n{seq}\n+\n{qual}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    # 2 条 PE read：R1 低质量尾（!），R2 正常 —— 仅作 argv 测试外观，不真跑 perl
    write_fastq(outdir / "r1.fq", [
        ("r1/1", "ACGTACGTACGTACGTACGTACGTACGT", "IIIIIIIIIIIIIIIIII!!!!!!!"),
        ("r2/1", "TTTTGGGGCCCCAAAATTTTGGGGCCCCAA", "IIIIIIIIIIIIIIIIIIIIIIIIIIII"),
    ])
    write_fastq(outdir / "r2.fq", [
        ("r1/2", "ACGTTGCATGCAACGTACGTACGTACGTAC", "IIIIIIIIIIIIIIIIIIIIIIIIIIII"),
        ("r2/2", "AAAACCCCGGGGTTTTAAAACCCCGGGGTTT", "IIIIIIIIIIIIIIII!!IIIIIIIIIII"),
    ])
    write_fastq(outdir / "single.fq", [
        ("s1", "ACGTACGTNNACGTACGTACGTACGTACGT", "IIIIIIIIIIIIIIIIIIIIIIIIIIII"),
        ("s2", "TTTTGGGGCCCCAAAATTTTGGGGCCCCAA", "IIIIIIIIIIIIIIIIIIIIIIIIIIII"),
    ])

    # 最小 toolkit 骨架：仅满足 main.py 脚本存在性断言
    tk = outdir / "fake-toolkit"
    for rel in ("QC/IlluQC_PRLL.pl", "Trimming/TrimmingReads.pl",
                "Trimming/AmbiguityFiltering.pl"):
        p = tk / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("#!/usr/bin/env perl\n# test stub (argv 构造测试用)\n", encoding="utf-8")

    print(f"已生成 NGSQCToolkit 测试数据 -> {outdir}（r1/r2/single.fq + fake-toolkit/）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
