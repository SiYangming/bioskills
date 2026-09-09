#!/usr/bin/env python3
"""生成 bless native 测试用的合成 reads（纯 Python，保持仓库轻量）。

产出（全部确定性生成，无外部依赖）：
  <outdir>/reads_1.fastq   双端 R1（~90% 干净 reads + ~10% 单碱基替换错误 reads）
  <outdir>/reads_2.fastq   双端 R2（与 R1 配对）
  <outdir>/single.fastq    单端 reads（correct 子命令单端模式用）

说明：BLESS 真跑需要 bless 已安装 + KMC（运行期 CWD 需 kmc/bin/kmc），且 k-mer 计数对
合成小数据仍要跑通 KMC 与 Bloom filter；run_test.sh 默认只做「argv 构造验证 + 无参用法
冒烟」，完整错误修正冒烟需显式 BLESS_FULL_SMOKE=1（见 run_test.sh）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

READ_LEN = 60
N_PAIRS = 120
N_SE = 60
SEED = 42


def _make_genome() -> str:
    """确定性伪随机 400 bp '基因组'（不含 N，便于错误注入）。"""
    rng = random.Random(SEED)
    return "".join(rng.choice("ACGT") for _ in range(400))


def _fragment(rng: random.Random, genome: str) -> str:
    start = rng.randrange(0, len(genome) - READ_LEN + 1)
    return genome[start:start + READ_LEN]


def _mutate(rng: random.Random, seq: str, n_err: int = 1) -> str:
    """把 seq 中随机 n_err 个位点替换成其它碱基（模拟测序错误）。"""
    bases = "ACGT"
    seq = list(seq)
    for pos in rng.sample(range(len(seq)), n_err):
        seq[pos] = rng.choice([b for b in bases if b != seq[pos]])
    return "".join(seq)


def write_fastq(path: Path, rng: random.Random, genome: str, n: int, paired_other: Path | None = None) -> None:
    with open(path, "w") as fh:
        for i in range(n):
            clean = _fragment(rng, genome)
            # 每 ~10 条放 1 条带单碱基错误的 reads；R2 与 R1 同源但独立抽样（非真实配对距离，
            # 仅用于跑通工具链路）
            seq = _mutate(rng, clean, 1) if rng.randrange(10) == 0 else clean
            fh.write(f"@synth_{i + 1}\n{seq}\n+\n{'I' * READ_LEN}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(SEED)
    genome = _make_genome()
    write_fastq(outdir / "reads_1.fastq", rng, genome, N_PAIRS)
    write_fastq(outdir / "reads_2.fastq", rng, genome, N_PAIRS)
    write_fastq(outdir / "single.fastq", rng, genome, N_SE)
    for f in ("reads_1.fastq", "reads_2.fastq", "single.fastq"):
        assert (outdir / f).stat().st_size > 0, f
    print(f"已生成测试数据 -> {outdir}（{N_PAIRS} 对双端 + {N_SE} 条单端）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
