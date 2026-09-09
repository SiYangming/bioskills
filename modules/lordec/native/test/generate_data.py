#!/usr/bin/env python3
"""生成 lordec native 测试用合成数据。

产出（全部纯 Python 生成，保持仓库轻量）：
  <outdir>/illumina.r1.fq      Illumina 样 R1 短读（paired，80bp × N）
  <outdir>/illumina.r2.fq      Illumina 样 R2 短读
  <outdir>/reads.fa            PacBio 样长读（含替换/插入/删除错误；可作 lordec-correct -i）

生成逻辑：固定随机种子 → 随机模板（~800bp）→ 短读从模板成对采样（保证 k=17 的 k-mer 有
solid 覆盖）；长读从模板全长拷贝并随机引入错误（substitution/indel），更接近真实使用。

说明：run_test.sh 以 argv 构造 + 自省断言为主（不依赖真实 lordec 二进制）；本数据供 lordec
二进制已安装时的 -h 冒烟或用户在本地做端到端冒烟使用。lordec-correct 真跑最小回归需要足够
的 k-mer 覆盖与合适 -k/-s，脚本不做完整纠错断言（避免合成数据假阴性）。
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

_SEED = 42
_BASES = "ACGT"


def _rand_seq(rng: random.Random, n: int) -> str:
    return "".join(rng.choice(_BASES) for _ in range(n))


def _mutate(rng: random.Random, seq: str, rate: float = 0.10) -> str:
    """按率引入替换/插入/删除错误（PacBio 样：indel 多于替换）。"""
    out: list[str] = []
    i = 0
    while i < len(seq):
        r = rng.random()
        if r < rate * 0.5:
            # 替换
            out.append(rng.choice(_BASES))
            i += 1
        elif r < rate * 0.8:
            # 插入
            out.append(seq[i])
            out.append(rng.choice(_BASES))
            i += 1
        elif r < rate:
            # 删除
            i += 1
        else:
            out.append(seq[i])
            i += 1
    return "".join(out)


def write_fastq_pair(path1: Path, path2: Path, template: str, n_pairs: int = 60, read_len: int = 80) -> None:
    """从模板成对采样短读（无错误：模拟高质量 Illumina），写 R1/R2 FASTQ。"""
    rng = random.Random(_SEED)
    with open(path1, "w") as f1, open(path2, "w") as f2:
        for n in range(n_pairs):
            start = rng.randint(0, max(0, len(template) - read_len))
            r1 = template[start:start + read_len]
            r2 = template[start:start + read_len]
            qual = "I" * read_len
            f1.write(f"@illumina_{n}/1\n{r1}\n+\n{qual}\n")
            f2.write(f"@illumina_{n}/2\n{r2}\n+\n{qual}\n")


def write_pacbio_fasta(path: Path, template: str, n_reads: int = 8) -> None:
    """生成 PacBio 样长读 FASTA（带错误），行长 60 折行。"""
    rng = random.Random(_SEED + 1)
    with open(path, "w") as fh:
        for n in range(n_reads):
            seq = _mutate(rng, template)
            fh.write(f">pacbio_read_{n}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(_SEED)
    template = _rand_seq(rng, 800)
    write_fastq_pair(outdir / "illumina.r1.fq", outdir / "illumina.r2.fq", template)
    write_pacbio_fasta(outdir / "reads.fa", template)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
