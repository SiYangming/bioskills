#!/usr/bin/env python3
"""生成 ninja native 测试用的合成数据。

产出（<outdir> 下）：
  aln.fa     比对 FASTA：9 条等长序列（3 组 × 3 条，组内相同、组间差异明显），
             用于 cluster 的 --in_type a（默认）最小链路（--cluster_cutoff 0.5 应聚成 3 簇）
  dist.phy   Phylip 风格距离矩阵：6 条序列（2 组 × 3 条），用于 cluster 的 --in_type d

说明：合成序列仅用于验证命令构造与产物落盘；真实重复序列聚类请用 RepeatModeler 产出的
consensi.fa / 比对结果（NINJA 由 modules/repeatmodeler 调用）。
"""
from __future__ import annotations

import sys
from pathlib import Path

GROUP_A = "ACGT" * 15   # 组 A（60 bp）
GROUP_B = "TTTA" * 15   # 组 B
GROUP_C = "GGCA" * 15   # 组 C（仅比对用）


def write_fasta(path: Path, seqs: dict[str, str]) -> None:
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_phylip(path: Path, names: list[str], dist: dict[tuple[str, str], float]) -> None:
    with open(path, "w") as fh:
        fh.write(f"{len(names)}\n")
        for n1 in names:
            row = [f"{n1}"]
            for n2 in names:
                row.append(f"{dist.get((n1, n2), 0.0):.6f}")
            fh.write(" ".join(row) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    # 比对 FASTA：3 组 × 3 条等长序列
    aln = {
        "repA1": GROUP_A, "repA2": GROUP_A, "repA3": GROUP_A,
        "repB1": GROUP_B, "repB2": GROUP_B, "repB3": GROUP_B,
        "repC1": GROUP_C, "repC2": GROUP_C, "repC3": GROUP_C,
    }
    write_fasta(outdir / "aln.fa", aln)

    # 距离矩阵：2 组 × 3 条（组内距离 0，组间 3.0）
    names = ["dmA1", "dmA2", "dmA3", "dmB1", "dmB2", "dmB3"]
    dist: dict[tuple[str, str], float] = {}
    for n1 in names:
        for n2 in names:
            if n1[2] != n2[2]:   # 组别字符 A/B 不同 → 组间距离 3.0
                dist[(n1, n2)] = 3.0
    write_phylip(outdir / "dist.phy", names, dist)

    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
