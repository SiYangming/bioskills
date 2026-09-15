#!/usr/bin/env python3
"""生成 fusionmap native 测试用的合成输入。

FusionMap 需要官方参考数据（Data/Ref）与真实 FASTQ 才能检测融合，且软件本体需从官方下载页
获取（商业/许可受限），合成数据无法覆盖真实计算。因此本脚本生成「占位 FASTQ + Ref 目录占位」，
run_test.sh 统一采用「python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/reads_1.fastq     单/双端 mate1 占位
  <outdir>/reads_2.fastq     双端 mate2 占位
  <outdir>/single.fastq      单端占位
  <outdir>/Ref/              参考数据目录占位（含 README 说明）
"""
from __future__ import annotations

import sys
from pathlib import Path


def _fastq(read_name: str) -> str:
    return f"@{read_name}\nACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIII\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "reads_1.fastq").write_text(_fastq("r1"), encoding="utf-8")
    (outdir / "reads_2.fastq").write_text(_fastq("r2"), encoding="utf-8")
    (outdir / "single.fastq").write_text(_fastq("s1"), encoding="utf-8")

    refdir = outdir / "Ref"
    refdir.mkdir(exist_ok=True)
    (refdir / "README.placeholder").write_text(
        "# PLACEHOLDER: FusionMap 参考数据目录（官方包内 Data/Ref）\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
