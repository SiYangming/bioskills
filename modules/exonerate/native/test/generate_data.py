#!/usr/bin/env python3
"""生成 exonerate native 测试用的合成输入。

exonerate 需要真实序列才能做比对，合成数据无法覆盖真实计算。因此本脚本生成
「可被命令构造读取的迷你 FASTA」，run_test.sh 在 exonerate 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」（不依赖已安装二进制）。

产出：
  <outdir>/homolog.fasta   迷你同源蛋白 FASTA（align/parallel 的 query）
  <outdir>/genome.fasta    迷你基因组 DNA FASTA（align/parallel 的 target）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "homolog.fasta").write_text(
        ">homolog1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">homolog2\nMALWMRLLPLLALLALWGPDPAAAFVNQHLCGSHLVE\n",
        encoding="utf-8",
    )
    (outdir / "genome.fasta").write_text(
        ">chr1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAATTTCTTTTGTGAAATCTCACTTTTCTCGCCAG\n"
        "CTAGAAGAACGTCTTGGTCTTATTGAAGTTCAGTAA\n",
        encoding="utf-8",
    )
    print(f"已生成测试迷你 FASTA -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
