#!/usr/bin/env python3
"""生成 soapdenovo2 native 测试用的合成输入。

SOAPdenovo2 all 需要真实 Illumina reads + config.txt 才能建图组装，合成数据无法覆盖真实计算。
因此本脚本生成「可解析的 config.txt + 占位 reads + 说明」，run_test.sh 在二进制未安装时
退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/config.txt          SOAPdenovo2 配置文件（max_rd_len + 两个 [LIB] 段，仿文档示例）
  <outdir>/fragment.1.fastq    文本占位（paired-end read1）
  <outdir>/fragment.2.fastq    文本占位（paired-end read2）
  <outdir>/jumping.1.fastq     文本占位（mate-pair read1）
  <outdir>/jumping.2.fastq     文本占位（mate-pair read2）
"""
from __future__ import annotations

import sys
from pathlib import Path


CONFIG = """max_rd_len=101
[LIB]
avg_ins=177
reverse_seq=0
asm_flags=1
rd_len_cutoff=100
rank=1
pair_num_cutoff=3
map_len=32
q1={d}/fragment.1.fastq
q2={d}/fragment.2.fastq
[LIB]
avg_ins=3000
reverse_seq=1
asm_flags=2
rd_len_cutoff=63
rank=2
pair_num_cutoff=5
map_len=35
q1={d}/jumping.1.fastq
q2={d}/jumping.2.fastq
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    for name in ("fragment.1.fastq", "fragment.2.fastq",
                 "jumping.1.fastq", "jumping.2.fastq"):
        (outdir / name).write_text(
            "# PLACEHOLDER: SOAPdenovo2 需真实 Illumina reads 才能建图组装\n",
            encoding="utf-8",
        )
    (outdir / "config.txt").write_text(CONFIG.format(d=outdir), encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
