#!/usr/bin/env python3
"""samtools / official_snakemake 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 wrapper 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 samtools。

用法：
  python wrapper.py <subcommand> [--threads N] [--output-format BAM]

或作为模块导入：
  from wrapper import SamtoolsWrapperBridge
  bridge = SamtoolsWrapperBridge()
  print(bridge.rule("sort"))
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/samtools"
DEFAULT_TAG = "v3.13.0"

# 子命令 -> 默认参数 / 资源建议
SUBCOMMAND_DEFAULTS = {
    "sort": {"threads": 8, "mem_mb": 8192},
    "view": {"threads": 4, "mem_mb": 4096},
    "mpileup": {"threads": 4, "mem_mb": 8192},
    "merge": {"threads": 4, "mem_mb": 8192},
    "index": {"threads": 1, "mem_mb": 2048},
    "flagstat": {"threads": 1, "mem_mb": 2048},
    "idxstats": {"threads": 1, "mem_mb": 2048},
    "stats": {"threads": 2, "mem_mb": 4096},
    "depth": {"threads": 1, "mem_mb": 2048},
    "faidx": {"threads": 1, "mem_mb": 1024},
    "quickcheck": {"threads": 1, "mem_mb": 1024},
    "dict": {"threads": 1, "mem_mb": 1024},
}


class SamtoolsWrapperBridge:
    """封装官方 wrapper 路径、版本与默认资源建议。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        """返回 Snakemake rule 中应引用的 wrapper 路径。"""
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 4, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        """生成可直接嵌入 Snakefile 的 rule 模板字符串。"""
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        # 以 sort 为例，其它子命令按需调整 input/output
        return (
            f"rule samtools_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{sample}}.bam\"\n"
            f"    output:\n"
            f"        \"{{sample}}.{subcommand}.bam\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 samtools 官方 wrapper rule 模板")
    p.add_argument("subcommand", help="samtools 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = SamtoolsWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
