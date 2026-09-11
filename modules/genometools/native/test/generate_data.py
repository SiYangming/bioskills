#!/usr/bin/env python3
"""生成 genometools native 测试用的合成小基因组（含一个 LTR 反转录转座子样结构）。

产出（<outdir>/genome.fa）：
  chr1  约 2.7 kb：5' 侧翼随机区 + TSD + LTR(150bp) + inner(1200bp) + TSD + 同一 LTR(150bp) + 3' 侧翼
  chr2  约 1.0 kb：纯随机序列（对照）

说明：
- 动态生成、体积 <5 KB，仅用于 run_test.sh 的 suffixerator → ltrharvest 最小链路回归；
  两条 LTR 拷贝完全相同（150bp ≥ ltrharvest 默认 seed 30），LTR 起始间距 1350bp 落在默认
  mindistltr(1000)~maxdistltr(15000) 区间，LTR 长度 150bp 落在 minlenltr(100)~maxlenltr(1000)，
  预期 ltrharvest 至少可报出 1 个候选（供产物断言；不作为真实重复注释结论）。
- 序列固定（seed=20260910），可重复断言。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 20260910
_TSD = "AGCTT"          # 目标位点重复（target site duplication）
_LTR_LEN = 150
_INNER_LEN = 1200


def rand_seq(rng: random.Random, length: int, gc: float = 0.42) -> str:
    """生成伪随机 DNA 片段（gc 为 GC 比例）。"""
    pool = "GC" * int(round(gc * 10)) + "AT" * int(round((1 - gc) * 10))
    return "".join(rng.choice(pool) for _ in range(length))


def write_fasta(path: Path) -> None:
    rng = random.Random(_SEED)
    ltr = rand_seq(rng, _LTR_LEN, gc=0.5)
    inner = rand_seq(rng, _INNER_LEN, gc=0.45)
    # LTR-inner-LTR 结构，两端各带 5bp TSD
    chr1 = (rand_seq(rng, 600) + _TSD + ltr + inner + _TSD + ltr + rand_seq(rng, 600))
    chr2 = rand_seq(rng, 1000)
    with open(path, "w") as fh:
        for name, seq in (("chr1", chr1), ("chr2", chr2)):
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "genome.fa")
    print(f"已生成合成小基因组 -> {outdir / 'genome.fa'}（2 条 contig，含 1 个 LTR 样结构）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
