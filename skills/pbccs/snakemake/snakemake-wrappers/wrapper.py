#!/usr/bin/env python3
"""pbccs / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 ccs。

注意：官方 snakemake-wrappers 目前【没有】bio/pbccs wrapper（抓取 404），
wrapper_path() 返回的句柄仅作占位登记；实际 Snakemake 场景请使用
skills/pbccs/snakemake/local/rule_pbccs.smk（pbccs_snakemake_local）。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import PbccsWrapperBridge
  bridge = PbccsWrapperBridge()
  print(bridge.rule("ccs"))
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/pbccs"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "ccs": {"threads": 8, "mem_mb": 16384},
}


class PbccsWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议（官方缺失占位）。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 8, "mem_mb": 16384})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        return (
            f"rule pbccs_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{sample}}.subreads.bam\"\n"
            f"    output:\n"
            f"        \"{{sample}}.ccs.bam\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
            f"# 注意：官方 bio/pbccs wrapper 不存在；请改用 ../local/rule_pbccs.smk\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 pbccs snakemake-wrappers 的 rule 模板（官方缺失占位）")
    p.add_argument("subcommand", help="pbccs 子命令（ccs）")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = PbccsWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
