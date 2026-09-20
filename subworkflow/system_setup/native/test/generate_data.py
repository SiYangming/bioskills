#!/usr/bin/env python3
"""生成 system_setup 测试占位（无真实系统依赖）。"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    (out / "software").mkdir(exist_ok=True)
    (out / "software" / "README.placeholder").write_text(
        "# PLACEHOLDER software cache for system_setup dry-run\n",
        encoding="utf-8",
    )
    print(f"已生成 system_setup 测试占位 -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
