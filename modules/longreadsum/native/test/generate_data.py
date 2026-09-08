#!/usr/bin/env python3
"""生成 longreadsum native 测试用的合成数据。

产出（全部纯 Python 生成，保持仓库轻量）：
  <outdir>/reads.fa       ONT 样 FASTA reads（fa 子命令真跑用）
  <outdir>/reads.fastq    最小 FASTQ（fq 子命令真跑用）
  <outdir>/reads.bam      纯 Python 手工编码的 BGZF/BAM（bam 子命令真跑用，可选）
  <outdir>/reads.summary  sequencing_summary.txt 样式占位（seqtxt 真跑用，可选）

不依赖 longreadsum / samtools / pysam：BAM 二进制与 BGZF 压缩全部用标准库实现。
说明：longreadsum 真跑需要 longreadsum 已安装；测试脚本会探测并退化为 argv 构造自检。
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

# BAM 碱基编码：A=1 C=2 G=4 T=8（低 4 位为 0 的为 N）；CIGAR: M=0
_BASE_BITS = {"A": 1, "C": 2, "G": 4, "T": 8}
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


def _encode_alignment(rec: dict) -> bytes:
    name = rec["name"].encode() + b"\x00"
    cigar = struct.pack("<I", (len(rec["seq"]) << 4) | 0)  # 全 M
    seq = b""
    for i in range(0, len(rec["seq"]), 2):
        hi = _BASE_BITS.get(rec["seq"][i], 15)
        lo = _BASE_BITS.get(rec["seq"][i + 1], 0) if i + 1 < len(rec["seq"]) else 0
        seq += bytes([(hi << 4) | lo])
    l_seq = len(rec["seq"])
    qual = bytes([rec.get("qual", 30)]) * l_seq
    core = struct.pack(
        "<iiBBHHHiiii",
        rec["ref_id"], rec["pos"], len(name), rec.get("mapq", 60),
        _reg2bin(rec["pos"], rec["pos"] + len(rec["seq"])),
        1, rec["flag"], l_seq, -1, -1, 0,
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


def write_fasta(path: Path) -> None:
    seq = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT" * 5  # 320 bp
    with open(path, "w") as fh:
        fh.write(f">read1 {''.join('I' * 40)}\n")
        for i in range(0, len(seq), 60):
            fh.write(seq[i:i + 60] + "\n")
        fh.write(">read2\n")
        for i in range(0, len(seq), 60):
            fh.write(seq[i:i + 60] + "\n")
        fh.write(">read3\n")
        for i in range(0, len(seq), 60):
            fh.write(seq[i:i + 60] + "\n")


def write_fastq(path: Path) -> None:
    seq = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"  # 40 bp
    with open(path, "w") as fh:
        for n in (1, 2, 3):
            fh.write(f"@read{n}\n{seq}\n+\n{'I' * len(seq)}\n")


def write_bam(path: Path) -> None:
    """手工构造一个合法的最小坐标排序 BAM（供 bam 子命令真跑；参考 gstama 同款编码）。"""
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
        dict(ref_id=0, pos=0, name="read1", flag=0, mapq=60, seq=seq),
        dict(ref_id=0, pos=100, name="read2", flag=0, mapq=60, seq=seq),
        dict(ref_id=-1, pos=0, name="read3", flag=4, mapq=0, seq=seq),
    ]
    for r in reads:
        rec = _encode_alignment(r)
        body += struct.pack("<i", len(rec))
        body += rec
    with open(path, "wb") as fh:
        fh.write(_bgzf_compress(bytes(body)))


def write_summary(path: Path) -> None:
    """sequencing_summary.txt 占位（列名与官方 guppy/dorado 输出一致；真跑可选）。"""
    with open(path, "w") as fh:
        fh.write("filename\tread_id\trun_id\tchannel\tmux\tstart_time\tduration\tnum_events\t"
                 "template_start\tnum_adapter_events\tsequence_length\tmean_qscore\n")
        for n in (1, 2):
            fh.write(f"sample.fast5\tread{n}\trun_1\t1\t1\t0\t10\t100\t0\t0\t50\t15.0\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)
    write_fasta(outdir / "reads.fa")
    write_fastq(outdir / "reads.fastq")
    write_bam(outdir / "reads.bam")
    write_summary(outdir / "reads.summary")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
