#!/usr/bin/env python3
"""生成 infernal native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fa  微型合成基因组（两条 contig，各约 1.0–1.3 kb，随机碱基，可作 cmsearch 目标序列库）

说明：
- Infernal 的最小真实回归需要「合法且已校准的 CM 数据库」（cmbuild+cmcalibrate 或直接下载
  Rfam.cm），迷你真 CM 无法在测试脚本内简单合成，因此 run_test.sh 的真跑链路为可选项：
  由环境变量 RFAM_CM 指向用户已有的真实 Rfam.cm（或其子集 .cm）时才会执行 cmpress → cmsearch；
  否则仅跑自省/帮助契约链路（见 run_test.sh）。
- 本文件只负责把搜索目标序列（genome.fa）动态生成出来，保持仓库轻量、不提交大文件。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 42
N_CONTIGS = 2
LENGTHS = (1280, 1040)


def rand_seq(length: int, rng: random.Random) -> str:
    return "".join(rng.choice("ACGT") for _ in range(length))


def write_fasta(path: Path, seqs: dict[str, str]) -> None:
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    seqs = {f"contig{i:02d}": rand_seq(LENGTHS[i - 1], rng) for i in range(1, N_CONTIGS + 1)}
    write_fasta(outdir / "genome.fa", seqs)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
