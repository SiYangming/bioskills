#!/usr/bin/env python3
"""ultra / snakemake / snakemake-wrappers 本地桥接脚本。

⚠️ 官方 snakemake-wrappers 的 bio/ultra 目录不存在（GitHub API 404，2026-08 核对）。
本脚本仅保留 samtools 风格的桥接 API（wrapper_path / defaults / rule），
但 wrapper_path() 明确标注官方句柄不可用，rule() 生成的是指向
../local/ultra.smk 的降级规则参考。本身不执行 ultra。

用法：
  python wrapper.py index     # 打印降级 rule 参考
  python wrapper.py --status  # 打印官方 wrapper 存在性
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/ultra"
DEFAULT_TAG = "v3.13.0"
OFFICIAL_AVAILABLE = False  # 2026-08 核对：bio/ultra 404

SUBCOMMAND_DEFAULTS = {
    "index": {"threads": 8, "mem_mb": 8192},
    "align": {"threads": 8, "mem_mb": 8192},
    "sort": {"threads": 2, "mem_mb": 4096},
    "gunzip": {"threads": 1, "mem_mb": 2048},
}


class UltraWrapperBridge:
    """封装官方 snakemake-wrappers 路径（已知缺失）与降级规则参考。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def available(self) -> bool:
        return OFFICIAL_AVAILABLE

    def wrapper_path(self, subcommand: str) -> str:
        """返回官方句柄（仅说明用；当前官方缺失，不可被 Snakemake 解析）。"""
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 4, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        """生成降级 rule 参考：include ../local/ultra.smk 后 use 对应规则。"""
        d = self.defaults(subcommand)
        return (
            f"# 官方 wrapper 缺失（{self.wrapper_path(subcommand)} 不可解析），降级本地规则：\n"
            f"include: \"../local/ultra.smk\"\n"
            f"# 之后即可使用 ultra_{subcommand} 规则（默认 threads={d['threads']}, mem_mb={d['mem_mb']}）。"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="ultra snakemake-wrappers 桥接（官方缺失 → 降级 local）")
    p.add_argument("subcommand", nargs="?", help="ultra 子命令（gunzip/index/align/sort）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    p.add_argument("--status", action="store_true", help="打印官方 wrapper 存在性")
    args = p.parse_args(argv)

    bridge = UltraWrapperBridge(tag=args.tag)
    if args.status:
        print(f"official wrapper available: {bridge.available()}")
        print(f"wrapper_base: {WRAPPER_BASE}")
        return 0
    if not args.subcommand:
        p.print_help(sys.stderr)
        return 2
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
