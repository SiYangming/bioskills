#!/usr/bin/env python3
"""sra-tools / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 sra-tools。

注意：官方 bio/sra-tools 目前只有 fasterq-dump 一个 wrapper（2026-09 抓取）；
prefetch / fastq-dump 请使用 skills/sra-tools/snakemake/local/sra_tools.smk
（sra-tools_snakemake_local）。

用法：
  python wrapper.py fasterq-dump [--tag vX.Y.Z]

作为模块导入：
  from wrapper import SraToolsWrapperBridge
  bridge = SraToolsWrapperBridge()
  print(bridge.rule("fasterq-dump"))
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/sra-tools"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "fasterq-dump": {"threads": 8, "mem_mb": 8192},
    "prefetch": {"threads": 2, "mem_mb": 2048},
    "fastq-dump": {"threads": 4, "mem_mb": 4096},
}


class SraToolsWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 4, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        if subcommand != "fasterq-dump":
            # prefetch / fastq-dump 官方无 wrapper（2026-09 抓取 404），输出占位提示
            return (
                f"# 注意：官方 bio/sra-tools 无 {subcommand} wrapper（2026-09 抓取 404）；\n"
                f"# 实际请使用 skills/sra-tools/snakemake/local/sra_tools.smk（sra-tools_snakemake_local）。\n"
                f"rule sra_{subcommand.replace('-', '_')}:\n"
                f"    input:\n"
                f"        \"{{sample}}.sra\"\n"
                f"    output:\n"
                f"        \"{{sample}}.{subcommand}.fastq\"\n"
                f"    threads: {d['threads']}\n"
                f"    resources:\n"
                f"        mem_mb={d['mem_mb']}\n"
            )
        return (
            f"rule sra_fasterq_dump:\n"
            f"    input:\n"
            f"        \"{{sample}}.sra\"\n"
            f"    output:\n"
            f"        \"{{sample}}.fastq\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 sra-tools snakemake-wrappers 的 rule 模板")
    p.add_argument("subcommand", help="sra-tools 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = SraToolsWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
