#!/usr/bin/env python3
"""生成 isoseq3 native 测试用的合成输入。

产出：
  <outdir>/in.bam        最小有效的 BGZF/BAM（纯 python 构造，1 条 ref、0 条记录）
  <outdir>/primers.fasta 两条 Iso-Seq 引物序列

说明：isoseq3 refine 需要 lima 清理后的有效 ccs BAM 才有真实生物学输出；
本最小 BAM 用于「命令能启动 + 参数正确」级别的回归。run_test.sh 在 isoseq3
未安装时退化为「python 构造 argv 验证命令构建不崩溃」。
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path


def _bgzf_block(data: bytes) -> bytes:
    """把 data 压缩为单个 BGZF 块（含 BC/BSIZE extra field）。"""
    comp = zlib.compressobj(6, zlib.DEFLATED, -15)
    comp_data = comp.compress(data) + comp.flush()
    bsize = len(comp_data) + 25  # XLEN 起始至块末的总长 - 1
    header = (
        b"\x1f\x8b\x08\x04"          # ID1 ID2 CM FLG(FEXTRA)
        b"\x00\x00\x00\x00"          # MTIME
        b"\x00\xff"                  # XFL OS
        b"\x06\x00"                  # XLEN = 6
        b"\x42\x43\x02\x00"          # subfield "BC", len=2
        + struct.pack("<H", bsize)   # BSIZE
    )
    crc = zlib.crc32(data) & 0xFFFFFFFF
    return header + comp_data + struct.pack("<II", crc, len(data))


def build_min_bam() -> bytes:
    """构造最小 BAM 二进制（@HD + 1 条 ref，无比对记录）。"""
    text = b"@HD\tVN:1.6\tSO:unknown\n"
    ref_name = b"chr1"
    ref_len = 1000
    out = b"BAM\x01"
    out += struct.pack("<I", len(text)) + text
    out += struct.pack("<I", 1)                        # n_ref
    out += struct.pack("<I", len(ref_name)) + ref_name
    out += struct.pack("<I", ref_len)                  # l_ref
    return out


def write_min_bam(path: Path) -> None:
    payload = build_min_bam()
    with open(path, "wb") as fh:
        fh.write(_bgzf_block(payload))
        fh.write(_bgzf_block(b""))  # BGZF EOF marker


def write_primers(path: Path) -> None:
    seqs = {
        "NEB_5p": "AAGCAGTGGTATCAACGCAGAGTACATGGGG",
        "Clontech_3p": "AAGCAGTGGTATCAACGCAGAGTAC",
    }
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n{seq}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_min_bam(outdir / "in.bam")
    write_primers(outdir / "primers.fasta")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
