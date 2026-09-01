#!/usr/bin/env python3
"""orfanage / snakemake-wrappers 桥接（官方无 wrapper，降级提示）。"""

DEFAULT_TAG = "v3.13.0"


def wrapper_path(_cmd: str = "") -> str:
    raise NotImplementedError("官方 bio/orfanage wrapper 不存在；请使用 ../local/orfanage.smk")


def defaults(_cmd: str = "") -> dict:
    return {"threads": 4, "mem_mb": 8192}


def rule(_cmd: str = "") -> str:
    return (
        "rule orfanage:\n"
        "    # 官方 wrapper 缺失，请 include 本地规则：\n"
        "    #   include: \"modules/orfanage/snakemake/local/orfanage.smk\"\n"
        "    pass\n"
    )


if __name__ == "__main__":
    print(rule())
