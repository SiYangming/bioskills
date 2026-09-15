#!/usr/bin/env python3
"""生成 kent native 测试用的合成输入。

产出：
  <outdir>/genome.fa      两条短序列（faToTwoBit / blat 输入）
  <outdir>/query.fa       一条查询序列（blat 输入）
  <outdir>/chrom.sizes    chr1/chr2 长度（bedToBigBed 输入）
  <outdir>/regions.bed    bed6（bedToBigBed 输入）
说明：若宿主机未安装 kent 工具，run_test.sh 退化为「python 构造 argv 验证命令构建不崩溃」；
装了 faToTwoBit / twoBitToFa 则真实做 FASTA↔2bit 往返断言。
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ1 = "ACGTACGTACGTACGTACGTACGTACGTACGT"  # 32 bp
SEQ2 = "TTTTGGGGCCCCAAAATTTTGGGGCCCCAAAA"  # 32 bp


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "genome.fa").write_text(
        f">chr1\n{SEQ1}\n>chr2\n{SEQ2}\n", encoding="utf-8"
    )
    (outdir / "query.fa").write_text(
        f">q1\n{SEQ1[:24]}\n", encoding="utf-8"
    )
    (outdir / "chrom.sizes").write_text(
        f"chr1\t{len(SEQ1)}\nchr2\t{len(SEQ2)}\n", encoding="utf-8"
    )
    (outdir / "regions.bed").write_text(
        f"chr1\t0\t16\tregionA\t100\t+\nchr2\t8\t24\tregionB\t200\t-\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
