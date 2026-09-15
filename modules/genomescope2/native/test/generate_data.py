#!/usr/bin/env python3
"""生成 genomescope2 native 测试用的合成输入。

GenomeScope 2.0 的模型拟合需要真实 k-mer 直方图才能收敛；合成数据无法覆盖真实拟合。
因此本脚本生成「文本 k-mer 直方图 + 说明」，run_test.sh 在 genomescope.R 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/mer_counts.histo  两列 k-mer 频率直方图（count / species number，GenomeScope 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1]).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    # 合成 k-mer 直方图：低覆盖 error 峰 + 主峰（diploid 示意）
    rows = [
        (1, 1200000), (2, 900000), (3, 700000), (4, 500000),
        (5, 300000), (10, 50000), (15, 20000), (20, 120000),
        (21, 160000), (22, 150000), (23, 90000), (40, 30000),
    ]
    (outdir / "mer_counts.histo").write_text(
        "\n".join(f"{d}\t{v}" for d, v in rows) + "\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
