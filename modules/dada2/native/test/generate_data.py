#!/usr/bin/env python3
"""生成 dada2 native 测试用的合成输入。

DADA2 去噪需要真实扩增子测序数据与 R 环境，合成数据无法覆盖真实计算。因此本脚本
生成「结构合法的最小 fastq + 说明」，run_test.sh 在 R/dada2 未安装时退化为
「用 python 构造 argv 验证 R 脚本生成不崩溃」，安装了再跑真实冒烟。

产出（<outdir> 下）：
  sample_R1.fastq   单端 R1 合成 fastq（6 条 60bp 读长，质量串等长）
  sample_R2.fastq   双端 R2 合成 fastq（与 R1 等长，供双端模式断言）
  reads.txt         R1 路径列表（逗号分隔，供 learnErrors/denoise 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

READ_LEN = 60
N_READS = 6


def _write_fastq(path: Path, tag: str) -> None:
    seq = ("ACGT" * ((READ_LEN // 4) + 1))[:READ_LEN]
    qual = "I" * READ_LEN
    with open(path, "w", encoding="utf-8") as fh:
        for i in range(1, N_READS + 1):
            fh.write(f"@{tag}_read{i}\n{seq}\n+\n{qual}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    _write_fastq(outdir / "sample_R1.fastq", "sample")
    _write_fastq(outdir / "sample_R2.fastq", "sample")
    (outdir / "reads.txt").write_text(str(outdir / "sample_R1.fastq") + "\n", encoding="utf-8")
    print(f"已生成 dada2 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
