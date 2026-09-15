#!/usr/bin/env python3
"""生成 clustalw native 测试用的合成输入。

ClustalW 比对/建树需要真实同源序列才能产出有意义结果，合成数据无法覆盖真实计算；因此本
脚本只生成「结构正确的小型 FASTA / 比对文件」，run_test.sh 用 python 构造 argv 验证命令构建
（monkeypatch 二进制解析），不实际运行 clustalw。

产出：
  <outdir>/seqs.fasta    最小多序列蛋白 FASTA（align 输入）
  <outdir>/aln.fasta     占位比对文件（tree 输入）
  <outdir>/aln2.fasta    占位比对文件（profile 的第二组）
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

    (outdir / "seqs.fasta").write_text(
        ">seq1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">seq2\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVA\n"
        ">seq3\nMRTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">seq4\nMKTAYIAKQRQISFVKSHFSRQLEERLGLVEVQ\n",
        encoding="utf-8",
    )
    (outdir / "aln.fasta").write_text(
        ">seq1\nMKTAYIAKQR-QISFVKSHFSR\n"
        ">seq2\nMKTAYIAKQR-QISFVKSHFSR\n"
        ">seq3\nMKTAYIAKQR-QISFVKSHFSR\n",
        encoding="utf-8",
    )
    (outdir / "aln2.fasta").write_text(
        ">seq4\nMKTAYIAKQRQISFVKSHFSR\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
