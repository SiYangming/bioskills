#!/usr/bin/env python3
"""生成 ultra native 测试用的最小合成数据。

产出（<outdir>/）：
  genome.fa          微型参考基因组（2 条 contig）
  genes.gtf          微型注释（2 条 transcript，含 CDS/exon 行）
  reads.fa           微型长读 reads（与 t1 外显子拼接序列一致，供 align 测试）
  genome.fa.gz       genome.fa 的 gzip 压缩版（供 gunzip 子命令测试）
"""
from __future__ import annotations

import gzip
import sys
from pathlib import Path

EXON1 = "ACGT" * 25      # 100 bp（chr1:101-200）
EXON2 = "GATC" * 25      # 100 bp（chr1:301-400）


def write_fasta(path: Path, seqs: dict[str, str]) -> None:
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_gtf(path: Path) -> None:
    rows = [
        # seqname source feature start end score strand frame attribute
        "chr1\tsrc\ttranscript\t101\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";",
        "chr1\tsrc\texon\t101\t200\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";",
        "chr1\tsrc\tCDS\t101\t200\t.\t+\t0\tgene_id \"g1\"; transcript_id \"t1\";",
        "chr1\tsrc\texon\t301\t400\t.\t+\t.\tgene_id \"g1\"; transcript_id \"t1\";",
        "chr1\tsrc\tCDS\t301\t400\t.\t+\t0\tgene_id \"g1\"; transcript_id \"t1\";",
        "chr2\tsrc\ttranscript\t501\t700\t.\t-\t.\tgene_id \"g2\"; transcript_id \"t2\";",
        "chr2\tsrc\texon\t501\t600\t.\t-\t.\tgene_id \"g2\"; transcript_id \"t2\";",
        "chr2\tsrc\tCDS\t501\t600\t.\t-\t0\tgene_id \"g2\"; transcript_id \"t2\";",
    ]
    with open(path, "w") as fh:
        fh.write("\n".join(rows) + "\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    seqs = {
        # chr1: 1-100 Ns, 101-200 = EXON1, 201-300 Ns, 301-400 = EXON2
        "chr1": "N" * 100 + EXON1 + "N" * 100 + EXON2,
        "chr2": "GGCC" * 100,  # 400 bp
    }
    write_fasta(outdir / "genome.fa", seqs)

    write_gtf(outdir / "genes.gtf")

    # reads：t1 外显子拼接序列（exon1+exon2，200 bp），供 align 测试命中
    write_fasta(outdir / "reads.fa", {"read_t1": EXON1 + EXON2})

    # genome.fa.gz：供 gunzip 子命令测试
    with open(outdir / "genome.fa", "rb") as fin, gzip.open(outdir / "genome.fa.gz", "wb") as fout:
        fout.write(fin.read())

    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
