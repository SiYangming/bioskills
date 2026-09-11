#!/usr/bin/env python3
"""生成 primer3 native 测试用的合成数据。

产出（<outdir> 下）：
  template.fa   微型合成模板 FASTA（单条序列 CL1，约 360 bp，GC 含量偏向 50%）
  seq.txt       同一条模板的裸序列（单行，供 --template 便捷模式使用）
  settings.txt  由该模板生成的 Primer3 设置文本（misa_primer3.pl 风格 p3_settings_file：
                SEQUENCE_ID/SEQUENCE_TEMPLATE/PRIMER_TASK/PRIMER_PRODUCT_SIZE_RANGE/=）

说明：真实回归只断言 primer3_core 运行 exit 0（与输出是否含 PRIMER 键）；
合成序列上的引物设计成功与否不保证，因此测试不断言引物条数（详见 run_test.sh）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

SEED = 42
SEQ_ID = "CL1"
SEQ_LEN = 360
PRODUCT_RANGE = "100-200"  # 需 < SEQ_LEN 留出引物放置空间


def rand_seq(length: int, rng: random.Random) -> str:
    """GC 偏向 50% 的随机 DNA（避免纯随机极端 GC 导致设计必败）。"""
    bases: list[str] = []
    for _ in range(length):
        # 50% 概率进 GC 分支，内部再 1:1；AT 分支同理 → 期望 GC ≈ 50%
        if rng.random() < 0.5:
            bases.append(rng.choice("GC"))
        else:
            bases.append(rng.choice("AT"))
    return "".join(bases)


def write_fasta(path: Path, name: str, seq: str) -> None:
    with open(path, "w") as fh:
        fh.write(f">{name}\n")
        for i in range(0, len(seq), 60):
            fh.write(seq[i:i + 60] + "\n")


def write_settings(path: Path, name: str, seq: str) -> None:
    """misa_primer3.pl 风格 p3_settings_file（教学 settings 的最小超集，'=' 结尾）。"""
    lines = [
        f"SEQUENCE_ID={name}",
        f"SEQUENCE_TEMPLATE={seq}",
        "PRIMER_TASK=generic",
        f"PRIMER_PRODUCT_SIZE_RANGE={PRODUCT_RANGE}",
        "=",
    ]
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    seq = rand_seq(SEQ_LEN, rng)
    write_fasta(outdir / "template.fa", SEQ_ID, seq)
    (outdir / "seq.txt").write_text(seq + "\n")
    write_settings(outdir / "settings.txt", SEQ_ID, seq)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
