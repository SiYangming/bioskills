#!/usr/bin/env python3
"""生成 sratools_pipeline 编排测试用占位 SRR 列表（dry-run 不读真实 .sra，仅需列表文件）。"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    lines = [
        "# sratools_pipeline 测试 SRR 列表（占位 accession，勿真实下载）",
        "SRR10000001",
        "",
        "SRR10000002",
    ]
    (out / "SRR_Acc_List.txt").write_text("\n".join(lines) + "\n")
    print(f"已生成 sratools_pipeline 测试 SRR 列表 -> {out / 'SRR_Acc_List.txt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
