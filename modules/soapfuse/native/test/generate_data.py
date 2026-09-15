#!/usr/bin/env python3
"""生成 soapfuse native 测试用的合成输入。

SOAPfuse 需官方数据库、config.txt 与真实双端 RNA-seq reads 才能产出结果，合成数据无法覆盖
真实计算。因此本脚本生成「config.txt 占位 + 双端 FASTQ 占位 + 样本列表」，run_test.sh 统一
采用「python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/config.txt       官方 config/config.txt 占位（DB/PG/PS/PD/PA 前缀结构示意）
  <outdir>/raw_data/        双端 reads 目录（含 <sample>_1.fastq / _2.fastq 占位）
  <outdir>/sample.list      样本信息列表（每行一个样本，制表符分隔）
"""
from __future__ import annotations

import sys
from pathlib import Path

CONFIG = (
    "# PLACEHOLDER: SOAPfuse config（官方包内 config/config.txt）\n"
    "# DB_db_dir = /DATABASE_DIR/\n"
    "# PG_pg_dir = /TOOL_DIR/source/bin\n"
    "# PS_ps_dir = /TOOL_DIR/source\n"
    "# PD_all_out = /out_directory/\n"
    "# PA_all_fq_postfix = _[12].fastq\n"
)

FASTQ = "@r1\nACGTACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIIIIIII\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "config.txt").write_text(CONFIG, encoding="utf-8")

    datadir = outdir / "raw_data"
    datadir.mkdir(exist_ok=True)
    (datadir / "sampleA_1.fastq").write_text(FASTQ, encoding="utf-8")
    (datadir / "sampleA_2.fastq").write_text(FASTQ, encoding="utf-8")

    # 样本列表：制表符分隔（SampleID / 名称 / 属性 / 读长示意）
    (outdir / "sample.list").write_text("sampleA\tsampleA\tsampleA\t20\n", encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
