#!/usr/bin/env python3
"""gstama / snakemake / snakemake-wrappers 本地桥接脚本（官方缺失时的占位桥）。

注意：官方 snakemake-wrappers 仓库**不存在** bio/gstama 目录（API 404），
因此本桥接脚本不指向任何真实 wrapper；它只负责引导用户降级到 ../local/ 或 native。
保留 wrapper_path()/defaults()/rule() 三 API 以保持结构一致。

用法：
  python wrapper.py polyacleanup   # 打印降级指引
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/gstama"
DEFAULT_TAG = "v3.13.0"

# 官方子命令清单（对应 nf-core gstama 子模块名；bio/gstama 本身不存在）
SUBCOMMANDS = ("polyacleanup", "collapse", "filelist", "merge")

SUBCOMMAND_DEFAULTS = {
    "polyacleanup": {"threads": 1, "mem_mb": 4096},
    "collapse": {"threads": 1, "mem_mb": 8192},
    "filelist": {"threads": 1, "mem_mb": 1024},
    "merge": {"threads": 1, "mem_mb": 8192},
}


class GstamaWrapperBridge:
    """官方 bio/gstama 缺失时的占位桥：wrapper_path 恒返回 None 并提示降级。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str | None:
        """官方 bio/gstama 不存在：返回 None，表示不可用。"""
        return None

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 1, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        return (
            f"# 官方 snakemake-wrappers 无 bio/gstama（404），wrapper 无法解析。\n"
            f"# 请改用 ../local/ 的规则（include: \"rules/rule_gstama_{subcommand}.smk\"），\n"
            f"# 或直接调用 native：python modules/gstama/native/main.py {subcommand} ...\n"
            f"# （建议资源：threads={d['threads']}, mem_mb={d['mem_mb']}）\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="gstama snakemake-wrappers 占位桥（官方缺失，输出降级指引）")
    p.add_argument("subcommand", choices=SUBCOMMANDS, help="gstama 子命令（polyacleanup/collapse/filelist/merge）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag（仅记录，官方不存在）")
    args = p.parse_args(argv)
    bridge = GstamaWrapperBridge(tag=args.tag)
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
