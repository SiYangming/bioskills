#!/usr/bin/env python3
"""生成 deblur native 测试用的合成输入。

Deblur 去噪需要真实扩增子数据与参考数据库，合成数据无法覆盖真实计算。因此本脚本
生成「结构合法的最小 fasta + 说明」，run_test.sh 在 deblur 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」，安装了再跑真实冒烟。

产出（<outdir> 下）：
  demux.fasta                     去多路复用单端序列（若干条 150bp）
  ref.fasta                       正向参考数据库（88_otus 风格占位）
  chimera_removed/                去嵌合 fasta 目录（build-biom-table 输入）
    sample1.fasta.trim.derep.no_artifacts.msa.deblur.no_chimeras
"""
from __future__ import annotations

import sys
from pathlib import Path

SEQ_LEN = 150
N_SEQS = 4


def _seq(i: int) -> str:
    return ("ACGT" * ((SEQ_LEN // 4) + 1))[:SEQ_LEN][: SEQ_LEN - (i % 3)]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    (outdir / "chimera_removed").mkdir(parents=True, exist_ok=True)

    with open(outdir / "demux.fasta", "w", encoding="utf-8") as fh:
        for i in range(1, N_SEQS + 1):
            fh.write(f">sample1_{i}\n{_seq(i)}\n")

    with open(outdir / "ref.fasta", "w", encoding="utf-8") as fh:
        fh.write(f">ref_88_otus_1\n{_seq(0)}\n")

    suffix = ".fasta.trim.derep.no_artifacts.msa.deblur.no_chimeras"
    chim = outdir / "chimera_removed" / f"sample1{suffix}"
    with open(chim, "w", encoding="utf-8") as fh:
        for i in range(1, N_SEQS + 1):
            fh.write(f">sample1_{i}\n{_seq(i)}\n")

    print(f"已生成 deblur 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
