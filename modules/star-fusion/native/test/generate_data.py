#!/usr/bin/env python3
"""生成 star-fusion native 测试用的合成输入。

STAR-Fusion 需要预先构建/下载的 CTAT 资源库（含 STAR 索引）与真实 RNA-seq reads 才能检测融合，
合成数据无法覆盖真实计算。因此本脚本生成「CTAT 资源库目录占位 + 双端 FASTQ 占位」，run_test.sh
统一采用「python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/CTAT_resource_lib/   资源库目录占位（含 README 说明；真实库需从 CTAT 下载/构建）
  <outdir>/reads_1.fastq.gz     双端 mate1 占位（gzip）
  <outdir>/reads_2.fastq.gz     双端 mate2 占位（gzip）
  <outdir>/single.fastq.gz      单端占位（gzip）
"""
from __future__ import annotations

import gzip
import sys
from pathlib import Path

FASTQ = "@r1\nACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIII\n"


def _write_gz(path: Path) -> None:
    with gzip.open(path, "wt", encoding="utf-8") as fh:
        fh.write(FASTQ)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    libdir = outdir / "CTAT_resource_lib"
    libdir.mkdir(exist_ok=True)
    (libdir / "README.placeholder").write_text(
        "# PLACEHOLDER: CTAT_resource_lib（真实资源库需从 CTAT 下载或本地构建）\n",
        encoding="utf-8",
    )

    _write_gz(outdir / "reads_1.fastq.gz")
    _write_gz(outdir / "reads_2.fastq.gz")
    _write_gz(outdir / "single.fastq.gz")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
