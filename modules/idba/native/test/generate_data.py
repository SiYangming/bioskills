#!/usr/bin/env python3
"""生成 idba native 测试用的合成输入。

IDBA-UD 需要真实短读数据才能完成迭代组装；合成数据无法覆盖真实组装。
因此本脚本生成「迷你 FASTQ + FASTA 占位」，run_test.sh 在 idba 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/illumina.1.fastq   迷你 FASTQ（双端 read1）
  <outdir>/illumina.2.fastq   迷你 FASTQ（双端 read2）
  <outdir>/illumina.fasta     FASTA 占位（fq2fa --merge 产物示意 / idba_ud 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

_R1 = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"
_R2 = "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1]).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    for name, seq in (("illumina.1.fastq", _R1), ("illumina.2.fastq", _R2)):
        (outdir / name).write_text(
            f"@read1/1\n{seq}\n+\n{'I' * len(seq)}\n"
            f"@read2/1\n{seq[::-5]}\n+\n{'I' * len(seq)}\n",
            encoding="utf-8",
        )
    (outdir / "illumina.fasta").write_text(
        f">read1\n{_R1}\n>read2\n{_R2}\n", encoding="utf-8"
    )

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
