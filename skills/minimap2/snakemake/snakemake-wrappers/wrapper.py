#!/usr/bin/env python3
"""minimap2 / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 minimap2。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import Minimap2WrapperBridge
  bridge = Minimap2WrapperBridge()
  print(bridge.rule("aligner"))
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/minimap2"
DEFAULT_TAG = "v3.13.0"

# bio/minimap2 官方 wrapper 清单（2026-08 抓取）与资源建议
SUBCOMMAND_DEFAULTS = {
    "aligner": {"threads": 8, "mem_mb": 16384},
    "index": {"threads": 4, "mem_mb": 8192},
}


class Minimap2WrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 4, "mem_mb": 8192})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        if subcommand == "aligner":
            body = (
                f"rule minimap2_aligner:\n"
                f"    input:\n"
                f"        reads=\"{{sample}}.fa\",\n"
                f"        reference=\"ref.fa\"\n"
                f"    output:\n"
                f"        bam=\"{{sample}}.bam\"\n"
            )
        elif subcommand == "index":
            body = (
                f"rule minimap2_index:\n"
                f"    input:\n"
                f"        reference=\"ref.fa\"\n"
                f"    output:\n"
                f"        index=\"ref.fa.mmi\"\n"
            )
        else:
            body = (
                f"rule minimap2_{subcommand}:\n"
                f"    input:\n"
                f"        \"{{sample}}.fa\"\n"
                f"    output:\n"
                f"        \"{{sample}}.{subcommand}.out\"\n"
            )
        return (
            body
            + f"    threads: {d['threads']}\n"
            + f"    resources:\n"
            + f"        mem_mb={d['mem_mb']}\n"
            + f"    wrapper:\n"
            + f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 minimap2 snakemake-wrappers 的 rule 模板")
    p.add_argument("subcommand", help="minimap2 wrapper 名（aligner/index）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = Minimap2WrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
