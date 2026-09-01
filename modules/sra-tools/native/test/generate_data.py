#!/usr/bin/env python3
"""生成 sra-tools native 测试用的合成输入。

prefetch / fasterq-dump / fastq-dump 需要真实 SRA 文件与 NCBI 网络访问，
合成数据无法覆盖真实下载/转换。因此本脚本生成「文本占位 + 说明」，
run_test.sh 在 sra-tools 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/SRR_Acc_List.txt     模拟 nanoseq 的 SRR 列表文件
  <outdir>/sra/SRR12345678/SRR12345678.sra   文本占位（fastq-dump 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])

    (outdir / "SRR_Acc_List.txt").write_text(
        "SRR12345678\nSRR23456789\n", encoding="utf-8"
    )
    sra_dir = outdir / "sra" / "SRR12345678"
    sra_dir.mkdir(parents=True, exist_ok=True)
    (sra_dir / "SRR12345678.sra").write_text(
        "# PLACEHOLDER: prefetch/dump 需要真实 SRA 文件\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
