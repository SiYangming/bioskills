#!/usr/bin/env python3
"""dorado / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 dorado。

注意：官方 snakemake-wrappers 目前【没有】bio/dorado wrapper（2026-09 抓取 404），
因此 wrapper_path() 返回的句柄仅为占位；Snakemake 场景请使用
skills/dorado/snakemake/local/dorado.smk（dorado_snakemake_local）。

用法：
  python wrapper.py basecall [--tag vX.Y.Z]

作为模块导入：
  from wrapper import DoradoWrapperBridge
  bridge = DoradoWrapperBridge()
  print(bridge.rule("basecall"))
"""

from __future__ import annotations

import argparse
import sys

WRAPPER_BASE = "bio/dorado"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "basecall": {"threads": 8, "mem_mb": 16384, "model": "rna004_130bps_sup@v5.1.0"},
    "demux": {"threads": 4, "mem_mb": 4096},
}


class DoradoWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议（官方缺失，占位桥接）。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 4, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        return (
            f"# 注意：官方 bio/dorado 缺失（2026-09 抓取 404），以下模板为占位；\n"
            f"# 实际请使用 skills/dorado/snakemake/local/dorado.smk（dorado_snakemake_local）。\n"
            f"rule dorado_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{sample}}.pod5\"\n"
            f"    output:\n"
            f"        \"{{sample}}.{subcommand}.fastq\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 dorado snakemake-wrappers 的 rule 模板（占位桥接）")
    p.add_argument("subcommand", help="dorado 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = DoradoWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}（官方缺失，占位）")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
