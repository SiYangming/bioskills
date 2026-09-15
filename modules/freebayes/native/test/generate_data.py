#!/usr/bin/env python3
"""生成 freebayes native 测试用的合成输入。

freebayes call/parallel 需要真实 BAM（含比对读段）与参考索引才能产出 VCF，合成数据无法
覆盖真实检测计算。因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv
验证命令构建不崩溃（monkeypatch _resolve_binary，不依赖已安装 freebayes），并在已安装时
做 --version 冒烟。

产出：
  <outdir>/reference.fa        最小参考 FASTA（附 .fai 占位）
  <outdir>/reference.fa.fai    参考索引占位
  <outdir>/V1.bam / V2.bam     BAM 占位（call 输入）
  <outdir>/bams.txt            BAM 列表（--bam-list 输入）
  <outdir>/regions.bed         区域文件（parallel 输入）
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

    (outdir / "reference.fa").write_text(
        ">chr1\n" + "ACGT" * 250 + "\n>chr2\n" + "TGCA" * 250 + "\n",
        encoding="utf-8",
    )
    (outdir / "reference.fa.fai").write_text(
        "chr1\t1000\t6\t1000\t1001\nchr2\t1000\t1019\t1000\t1001\n",
        encoding="utf-8",
    )
    for name in ("V1.bam", "V2.bam"):
        (outdir / name).write_text(f"# PLACEHOLDER: freebayes 需要真实 sorted BAM ({name})\n",
                                   encoding="utf-8")
    (outdir / "bams.txt").write_text(
        f"{outdir / 'V1.bam'}\n{outdir / 'V2.bam'}\n", encoding="utf-8"
    )
    (outdir / "regions.bed").write_text(
        "chr1\t0\t500\nchr1\t500\t1000\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
