#!/usr/bin/env python3
"""生成 ltr_retriever native 测试用的合成数据。

产出（<outdir> 下）：
  genome.fa       含一个 LTR 反转录转座子样结构的合成小基因组（chr1 ~2.7kb + chr2 ~1kb 对照）
  ltrharvest.out  LTRharvest 候选文件（-out FASTA 格式；与 LTR_retriever -inharvest 配合）

说明：
- 动态生成、体积 <5 KB，仅用于 run_test.sh 的最小链路回归（genome.fa + ltrharvest.out 喂给
  LTR_retriever -genome / -inharvest），不作为真实重复注释结论。
- chr1 结构：5' 侧翼 + TSD + LTR(150bp) + inner(1200bp) + TSD + 同一 LTR(150bp) + 3' 侧翼；
  两条 LTR 拷贝完全相同、LTR 起始间距落在 LTRharvest 默认区间，作为候选的合理来源。
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


def write_fasta(path: Path, records: list[tuple[str, str]]) -> None:
    with open(path, "w") as fh:
        for name, seq in records:
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(_SEED)
    ltr = rand_seq(rng, _LTR_LEN, gc=0.5)
    inner = rand_seq(rng, _INNER_LEN, gc=0.45)
    chr1 = rand_seq(rng, 600) + _TSD + ltr + inner + _TSD + ltr + rand_seq(rng, 600)  # ~2.7 kb
    chr2 = rand_seq(rng, 1000)                                                        # 对照
    write_fasta(outdir / "genome.fa", [("chr1", chr1), ("chr2", chr2)])

    # LTRharvest -out 候选（FASTA：预测到的 LTR 序列；两条相同拷贝）
    write_fasta(outdir / "ltrharvest.out", [("chr1_LTR_1", ltr), ("chr1_LTR_2", ltr)])

    print(f"已生成测试数据 -> {outdir}（genome.fa 2 条 contig 含 1 个 LTR 样结构；ltrharvest.out 2 条 LTR 候选）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
