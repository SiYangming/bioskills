#!/usr/bin/env python3
"""orffinder / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 ORFfinder。

注意：官方 snakemake-wrappers 目前【没有】bio/orffinder wrapper（抓取 404），
wrapper_path() 返回的句柄仅作占位登记；实际 Snakemake 场景请使用
modules/orffinder/snakemake/local/orffinder.smk（orffinder_snakemake_local）。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import OrffinderWrapperBridge
  bridge = OrffinderWrapperBridge()
  print(bridge.rule("run"))
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/orffinder"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "run": {"threads": 1, "mem_mb": 4096},
}


class OrffinderWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议（官方缺失占位）。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self, subcommand: str) -> str:
        return f"{self.tag}/{WRAPPER_BASE}/{subcommand}"

    def defaults(self, subcommand: str) -> dict:
        return SUBCOMMAND_DEFAULTS.get(subcommand, {"threads": 1, "mem_mb": 4096})

    def rule(self, subcommand: str) -> str:
        d = self.defaults(subcommand)
        wp = self.wrapper_path(subcommand)
        return (
            f"rule orffinder_{subcommand}:\n"
            f"    input:\n"
            f"        \"{{sample}}.fa\"\n"
            f"    output:\n"
            f"        \"orffinder/{{sample}}.asn1\"\n"   # outfmt=2 默认后缀
            f"    params:\n"
            f"        outfmt=2, extra=\"-s 2 -ml 30\"\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
            f"# 注意：官方 bio/orffinder wrapper 不存在；请改用 ../local/orffinder.smk\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 orffinder snakemake-wrappers 的 rule 模板（官方缺失占位）")
    p.add_argument("subcommand", choices=sorted(SUBCOMMAND_DEFAULTS), help="orffinder 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = OrffinderWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
