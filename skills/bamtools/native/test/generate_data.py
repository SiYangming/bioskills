#!/usr/bin/env python3
"""生成 bamtools native 测试用的合成数据。

产出：
  <outdir>/reads.bam      纯 Python 手工编码的 BGZF/BAM（含 @HD/@SQ 头 + 4 条比对）
  <outdir>/refs.fa        微型参考序列（供索引/排序语义参考，非必需）

不依赖 samtools / pysam / bamtools：BAM 二进制与 BGZF 压缩全部用标准库实现，
保证测试环境零外部依赖即可生成输入。
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

# BAM 碱基编码：A=1 C=2 G=4 T=8 N=15（低 4 位为 0 的为 N）
_BASE_BITS = {"A": 1, "C": 2, "G": 4, "T": 8, "N": 15}
# CIGAR 操作码
_CIGAR_OPS = {"M": 0, "I": 1, "D": 2, "N": 3, "S": 4, "H": 5, "P": 6, "=": 7, "X": 8}


def _reg2bin(beg: int, end: int) -> int:
    """htslib reg2bin：由区间起点/终点计算 BAM bin。"""
    end -= 1
    if beg >> 14 == end >> 14:
        return ((1 << 15) - 1) // 7 + (beg >> 14)
    if beg >> 17 == end >> 17:
        return ((1 << 12) - 1) // 7 + (beg >> 17)
    if beg >> 20 == end >> 20:
        return ((1 << 9) - 1) // 7 + (beg >> 20)
    if beg >> 23 == end >> 23:
        return ((1 << 6) - 1) // 7 + (beg >> 23)
    if beg >> 26 == end >> 26:
        return ((1 << 3) - 1) // 7 + (beg >> 26)
    return 0


def _encode_cigar(cigar: list[tuple[int, str]]) -> bytes:
    out = b""
    for length, op in cigar:
        out += struct.pack("<I", (length << 4) | _CIGAR_OPS[op])
    return out


def _encode_seq(seq: str) -> bytes:
    out = b""
    for i in range(0, len(seq), 2):
        hi = _BASE_BITS.get(seq[i], 15)
        lo = _BASE_BITS.get(seq[i + 1], 0) if i + 1 < len(seq) else 0
        out += bytes([(hi << 4) | lo])
    return out


def _encode_alignment(rec: dict) -> bytes:
    """编码单条 BAM alignment record（core + 变长区）。"""
    name = rec["name"].encode() + b"\x00"
    l_read_name = len(name)
    cigar = _encode_cigar(rec["cigar"])
    seq = _encode_seq(rec["seq"])
    l_seq = len(rec["seq"])
    qual = bytes([rec.get("qual", 40)]) * l_seq
    core = struct.pack(
        "<iiBBHHHiiii",
        rec["ref_id"], rec["pos"], l_read_name, rec.get("mapq", 60),
        _reg2bin(rec["pos"], rec["pos"] + sum(l for l, _ in rec["cigar"])),
        len(rec["cigar"]), rec["flag"], l_seq, -1, -1, 0,
    )
    return core + name + cigar + seq + qual


# htslib/bgzf 的标准 EOF marker（28 字节常量），bamtools/samtools 依赖它识别文件正常结束；
# 缺少时会把 BAM 判为 truncated 并读到 0 条比对。
_BGZF_EOF = bytes.fromhex(
    "1f8b08040000000000ff0600424302001b0003000000000000000000"
)


def _bgzf_compress(data: bytes) -> bytes:
    """把整段数据打包为一个（或多个）BGZF 块。

    块 = gzip 头(10B) + FEXTRA(XLEN=6 + BC 子字段) + raw deflate 数据 + CRC32 + ISIZE。
    小测试数据单块即可；块大小断言 < 64KB。
    """
    if len(data) <= 0:
        return b""
    co = zlib.compressobj(6, zlib.DEFLATED, -15)
    cdata = co.compress(data) + co.flush()
    total = 18 + len(cdata) + 8  # 10 头 + 2 XLEN + 6 BC 子字段 + cdata + 8 trailer
    assert total <= 65536, "BGZF 块超过 64KB，需分块（测试数据不应触发）"
    header = b"\x1f\x8b\x08\x04" + b"\x00\x00\x00\x00" + b"\x00\xff"  # gzip + FEXTRA
    extra = struct.pack("<H", 6) + b"BC" + struct.pack("<H", 2) + struct.pack("<H", total - 1)
    trailer = struct.pack("<II", zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF)
    return header + extra + cdata + trailer + _BGZF_EOF


def write_bam(path: Path) -> None:
    """手工构造一个合法的最小 BAM（坐标已排序，供 index/sort 语义使用）。"""
    header_text = "@HD\tVN:1.6\tSO:coordinate\n@SQ\tSN:chr1\tLN:200\n@SQ\tSN:chr2\tLN:200\n"
    refs = [("chr1", 200), ("chr2", 200)]

    body = bytearray()
    body += b"BAM\x01"
    ht = header_text.encode()
    body += struct.pack("<i", len(ht))
    body += ht
    body += struct.pack("<i", len(refs))
    for name, ln in refs:
        nb = name.encode() + b"\x00"
        body += struct.pack("<i", len(nb))
        body += nb
        body += struct.pack("<i", ln)

    seq10 = "ACGTACGTAC"
    reads = [
        # ref_id, pos, name, flag, mapq, cigar, seq（坐标递增，未比对 read 放最后）
        dict(ref_id=0, pos=0, name="read1", flag=0, mapq=60, cigar=[(10, "M")], seq=seq10),
        dict(ref_id=0, pos=100, name="read2", flag=0, mapq=60, cigar=[(10, "M")], seq=seq10),
        dict(ref_id=1, pos=0, name="read3", flag=0, mapq=60, cigar=[(10, "M")], seq="TTGGCCAATT"),
        dict(ref_id=-1, pos=0, name="read4", flag=4, mapq=0, cigar=[], seq=seq10),
    ]
    for r in reads:
        # BAM 规格：每条 alignment 记录前有一个 int32 block_size（记录自身字节数）
        rec = _encode_alignment(r)
        body += struct.pack("<i", len(rec))
        body += rec

    with open(path, "wb") as fh:
        fh.write(_bgzf_compress(bytes(body)))


def write_fasta(path: Path) -> None:
    seqs = {
        "chr1": "ACGT" * 50,        # 200 bp
        "chr2": "TTGGCCAA" * 25,    # 200 bp
    }
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
    write_bam(outdir / "reads.bam")
    write_fasta(outdir / "refs.fa")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
