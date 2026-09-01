#!/usr/bin/env python3
"""transdecoder / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 TransDecoder。

官方 snakemake-wrappers 有 bio/transdecoder/{longorfs,predict} 两个 wrapper；
wrapper_path() 返回句柄，Snakemake 运行时按句柄解析执行。

用法：
  python wrapper.py <subcommand> [--tag vX.Y.Z]

作为模块导入：
  from wrapper import TransdecoderWrapperBridge
  bridge = TransdecoderWrapperBridge()
  print(bridge.rule("longorfs"))
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/transdecoder"
DEFAULT_TAG = "v3.13.0"

SUBCOMMAND_DEFAULTS = {
    "longorfs": {"threads": 4, "mem_mb": 8192},
    "predict": {"threads": 8, "mem_mb": 16384},
}


class TransdecoderWrapperBridge:
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
        if subcommand == "longorfs":
            output_line = '        directory("transdecoder/{sample}/longorfs")'
            extra_hint = '        params:\n            extra="-m 50 -G Universal -S"  # 可选'
        else:
            output_line = '        "transdecoder/{sample}/predict/{sample}.pep"'
            extra_hint = '        params:\n            extra="--no_refine_starts"  # 可选'
        return (
            f"rule transdecoder_{subcommand}:\n"
            f"    input:\n"
            f"        \"transcripts/{{sample}}.fa\"\n"
            f"    output:\n"
            f"        {output_line}\n"
            f"    threads: {d['threads']}\n"
            f"    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            f"{extra_hint}\n"
            f"    wrapper:\n"
            f"        \"{wp}\"\n"
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 transdecoder snakemake-wrappers 的 rule 模板")
    p.add_argument("subcommand", choices=sorted(SUBCOMMAND_DEFAULTS), help="transdecoder 子命令")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = TransdecoderWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path(args.subcommand)}")
    print(bridge.rule(args.subcommand))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
