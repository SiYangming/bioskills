#!/usr/bin/env python3
"""fastp / snakemake / snakemake-wrappers 本地桥接脚本。

作用：为 Snakemake 流程生成引用官方 snakemake-wrappers 的 rule 模板与默认参数，
避免在多处硬编码 wrapper 路径与版本。本身不执行 fastp。

用法：
  python wrapper.py [--tag vX.Y.Z]

作为模块导入：
  from wrapper import FastpWrapperBridge
  bridge = FastpWrapperBridge()
  print(bridge.rule())
"""

from __future__ import annotations

import argparse

WRAPPER_BASE = "bio/fastp"
DEFAULT_TAG = "v3.13.0"

DEFAULTS = {"threads": 8, "mem_mb": 8192}


class FastpWrapperBridge:
    """封装官方 snakemake-wrappers 路径、版本与默认资源建议。"""

    def __init__(self, tag: str = DEFAULT_TAG):
        self.tag = tag

    def wrapper_path(self) -> str:
        return f"{self.tag}/{WRAPPER_BASE}"

    def defaults(self) -> dict:
        return dict(DEFAULTS)

    def rule(self) -> str:
        d = self.defaults()
        wp = self.wrapper_path()
        return (
            "rule fastp:\n"
            "    input:\n"
            '        reads=[\"reads/{sample}_R1.fastq.gz\", \"reads/{sample}_R2.fastq.gz\"]\n'
            "    output:\n"
            '        reads=[\"results/fastp/{sample}_R1.clean.fastq.gz\",\n'
            '               \"results/fastp/{sample}_R2.clean.fastq.gz\"],\n'
            '        html=\"results/fastp/{sample}_fastp.html\",\n'
            '        json=\"results/fastp/{sample}_fastp.json\"\n'
            "    params:\n"
            '        extra=\"--detect_adapter_for_pe\"\n'
            f"    threads: {d['threads']}\n"
            "    resources:\n"
            f"        mem_mb={d['mem_mb']}\n"
            "    wrapper:\n"
            f'        "{wp}"\n'
        )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="生成 fastp snakemake-wrappers 的 rule 模板")
    p.add_argument("--tag", default=DEFAULT_TAG, help="wrapper 版本 tag")
    args = p.parse_args(argv)
    bridge = FastpWrapperBridge(tag=args.tag)
    print(f"# wrapper: {bridge.wrapper_path()}")
    print(bridge.rule())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
