#!/usr/bin/env python3
"""bamtools / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 bamtools。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import BamToolsWrapperBridge
  bridge = BamToolsWrapperBridge()
  print(bridge.rule("stats"))
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/bamtools"
DEFAULT_TAG = "v3.13.0"

# bio/bamtools 官方 wrapper 清单（2026-08 抓取）与资源建议
SUBCOMMAND_DEFAULTS = {
    "filter": {"threads": 2, "mem_mb": 4096},
    "filter_json": {"threads": 2, "mem_mb": 4096},
    "split": {"threads": 2, "mem_mb": 4096},
    "stats": {"threads": 1, "mem_mb": 2048},
}


class BamToolsWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 2, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        return (
            f"rule bamtools_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{sample}}.bam\"\n"
            f"    output:\n"
            f"        \"{{sample}}.{subcommand}.out\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 bamtools snakemake-wrappers 的 rule 模板")
    p.add_argument("subcommand", help="bamtools wrapper 名（filter/filter_json/split/stats）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = BamToolsWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
