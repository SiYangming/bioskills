#!/usr/bin/env python3
"""生成 gstama native 测试用的合成数据。

产出：
  <outdir>/refs.fa             微型参考序列（collapse 用）
  <outdir>/reads.fa            FLNC 样 reads（含 polyA 尾巴，polyacleanup 用）
  <outdir>/reads.bam           纯 Python 手工编码的 BGZF/BAM（坐标排序，collapse 用）
  <outdir>/beds/<aligner>/<sample>/<sample>.chunk<N>.bed  假 collapse bed（filelist 用）

不依赖 TAMA/samtools：BAM 二进制与 BGZF 压缩全部用标准库实现。
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
# htslib/bgzf 的标准 EOF marker（28 字节常量）
_BGZF_EOF = bytes.fromhex(
    "1f8b08040000000000ff0600424302001b0003000000000000000000"
)


def _reg2bin(beg: int, end: int) -> int:
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
    name = rec["name"].encode() + b"\x00"
    cigar = _encode_cigar(rec["cigar"])
    seq = _encode_seq(rec["seq"])
    l_seq = len(rec["seq"])
    qual = bytes([rec.get("qual", 40)]) * l_seq
    core = struct.pack(
        "<iiBBHHHiiii",
        rec["ref_id"], rec["pos"], len(name), rec.get("mapq", 60),
        _reg2bin(rec["pos"], rec["pos"] + sum(l for l, _ in rec["cigar"])),
        len(rec["cigar"]), rec["flag"], l_seq, -1, -1, 0,
    )
    return core + name + cigar + seq + qual


def _bgzf_compress(data: bytes) -> bytes:
    co = zlib.compressobj(6, zlib.DEFLATED, -15)
    cdata = co.compress(data) + co.flush()
    total = 18 + len(cdata) + 8
    assert total <= 65536, "BGZF 块超过 64KB，需分块（测试数据不应触发）"
    header = b"\x1f\x8b\x08\x04" + b"\x00" * 4 + b"\x00\xff"
    extra = struct.pack("<H", 6) + b"BC" + struct.pack("<H", 2) + struct.pack("<H", total - 1)
    trailer = struct.pack("<II", zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF)
    return header + extra + cdata + trailer + _BGZF_EOF


def write_bam(path: Path) -> None:
    """手工构造一个合法的最小 BAM（坐标已排序，未比对 read 放最后）。"""
    header_text = "@HD\tVN:1.6\tSO:coordinate\n@SQ\tSN:chr1\tLN:400\n"
    body = bytearray(b"BAM\x01")
    ht = header_text.encode()
    body += struct.pack("<i", len(ht))
    body += ht
    body += struct.pack("<i", 1)
    nb = b"chr1\x00"
    body += struct.pack("<i", len(nb))
    body += nb
    body += struct.pack("<i", 400)

    seq = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"  # 40 bp
    reads = [
        dict(ref_id=0, pos=0, name="read1", flag=0, mapq=60, cigar=[(40, "M")], seq=seq),
        dict(ref_id=0, pos=100, name="read2", flag=0, mapq=60, cigar=[(40, "M")], seq=seq),
        dict(ref_id=-1, pos=0, name="read3", flag=4, mapq=0, cigar=[], seq=seq),
    ]
    for r in reads:
        rec = _encode_alignment(r)
        body += struct.pack("<i", len(rec))  # BAM 规格：每条记录前有 block_size
        body += rec

    with open(path, "wb") as fh:
        fh.write(_bgzf_compress(bytes(body)))


def write_fasta(path: Path, seqs: dict[str, str]) -> None:
    with open(path, "w") as fh:
        for name, seq in seqs.items():
            fh.write(f">{name}\n")
            for i in range(0, len(seq), 60):
                fh.write(seq[i:i + 60] + "\n")


def write_reads(path: Path) -> None:
    """FLNC 样 reads：参考子串 + 3' polyA 尾巴（供 polyacleanup 识别）。"""
    seq = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"  # 60 bp
    reads = {
        "read1": seq + "A" * 25,
        "read2": seq + "A" * 15,
        "read3": seq,
    }
    write_fasta(path, reads)


def write_beds(base: Path) -> None:
    """生成假 collapse bed（bed12 内容非必需，filelist 只读取路径/名称）。"""
    for aligner, sample, chunk in (("minimap2", "sample1", "1"), ("minimap2", "sample1", "2")):
        d = base / aligner / sample
        d.mkdir(parents=True, exist_ok=True)
        with open(d / f"{sample}.chunk{chunk}_gstama_collapsed.bed", "w") as fh:
            fh.write(f"chr1\t0\t100\t{sample}.chunk{chunk}\t0\t+\t0\t100\t0\t1\t100,0\t0,\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "refs.fa", {"chr1": "ACGT" * 100})  # 400 bp
    write_reads(outdir / "reads.fa")
    write_bam(outdir / "reads.bam")
    write_beds(outdir / "beds")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
