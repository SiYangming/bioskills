#!/usr/bin/env python3
"""stringtie / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 stringtie。

注意：官方 snakemake-wrappers 目前【没有】bio/stringtie wrapper（抓取 404），
wrapper_path() 返回的句柄仅作占位登记；实际 Snakemake 场景请使用
skills/stringtie/snakemake/local/stringtie.smk（stringtie_snakemake_local）。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import StringtieWrapperBridge
  bridge = StringtieWrapperBridge()
  print(bridge.rule("assemble"))
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/stringtie"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "assemble": {"threads": 8, "mem_mb": 16384},
    "merge": {"threads": 4, "mem_mb": 8192},
    "fix_gtf": {"threads": 2, "mem_mb": 2048},
}


class StringtieWrapperBridge:
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
        if subcommand == "assemble":
            return (
                f"rule stringtie_assemble:\n"
                f"    input:\n"
                f"        \"alignment/{{sample}}.sorted.bam\"\n"
                f"    output:\n"
                f"        \"assembled/{{sample}}.stringtie.gtf\"\n"
                f"    threads: {d['threads']}\n"
                f"    resources:\n"
                f"        mem_mb={d['mem_mb']}\n"
                f"    wrapper:\n"
                f"        \"{wp}\"\n"
                f"# 注意：官方 bio/stringtie wrapper 不存在；请改用 ../local/stringtie.smk\n"
            )
        return (
            f"rule stringtie_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{input}}.in\"\n"
            f"    output:\n"
            f"        \"{{output}}.out\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
            f"# 注意：官方 bio/stringtie wrapper 不存在；请改用 ../local/stringtie.smk\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 stringtie snakemake-wrappers 的 rule 模板（官方缺失占位）")
    p.add_argument("subcommand", choices=["assemble", "merge", "fix_gtf"], help="stringtie 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = StringtieWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
