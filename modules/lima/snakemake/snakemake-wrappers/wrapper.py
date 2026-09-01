#!/usr/bin/env python3
"""lima / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 lima。

注意：官方 snakemake-wrappers 目前【没有】bio/lima wrapper（抓取 404），
wrapper_path() 返回的句柄仅作占位登记；实际 Snakemake 场景请使用
modules/lima/snakemake/local/lima.smk（lima_snakemake_local）。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import LimaWrapperBridge
  bridge = LimaWrapperBridge()
  print(bridge.rule("lima"))
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/lima"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "lima": {"threads": 8, "mem_mb": 8192},
}


class LimaWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议（官方缺失占位）。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 8, "mem_mb": 8192})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        return (
            f"rule lima_{subcommand}:\n"
            f"    input:\n"
            f"        bam=\"{{sample}}.ccs.bam\",\n"
            f"        primers=\"primers.fasta\"\n"
            f"    output:\n"
            f"        \"{{sample}}.demux.bam\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
            f"# 注意：官方 bio/lima wrapper 不存在；请改用 ../local/lima.smk\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 lima snakemake-wrappers 的 rule 模板（官方缺失占位）")
    p.add_argument("subcommand", help="lima 子命令（lima）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = LimaWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
