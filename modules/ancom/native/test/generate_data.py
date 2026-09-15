#!/usr/bin/env python3
"""生成 ancom native 测试用的合成输入。

ANCOM 的差异丰度计算需要真实丰度矩阵 + 满足组成性假设的分组才能产出有意义结果，
合成数据无法覆盖真实统计计算，因此本脚本生成「最小 OTU 表 + 元数据表」，
run_test.sh 在无 R 环境时退化为「用 python 构造 argv / params.tsv 验证命令构建不崩溃」。

产出：
  <outdir>/feature-table.tsv   特征丰度表（首列特征 id，其余列样本；两组各 2 样本）
  <outdir>/sample-metadata.tsv 样本元数据表（首列样本 id；含 Subject 分组列）
"""
from __future__ import annotations

import sys
from pathlib import Path

_FEATURE_TABLE = (
    "#OTU ID\tS1\tS2\tS3\tS4\n"
    "t1\t10\t12\t8\t9\n"
    "t2\t50\t48\t3\t2\n"
    "t3\t1\t1\t30\t28\n"
    "t4\t5\t6\t7\t6\n"
    "t5\t0\t1\t40\t42\n"
)

_METADATA = (
    "SampleID\tSubject\tBodySite\n"
    "S1\tA\tgut\n"
    "S2\tA\tgut\n"
    "S3\tB\tgut\n"
    "S4\tB\tgut\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "feature-table.tsv").write_text(_FEATURE_TABLE, encoding="utf-8")
    (outdir / "sample-metadata.tsv").write_text(_METADATA, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
