#!/usr/bin/env python3
"""生成 ensembl-vep native 测试用的合成输入。

VEP 注释需要本地缓存数据库（vep_install 下载的物种缓存）才能产出结果，合成数据无法覆盖
真实注释计算。因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv 验证
命令构建不崩溃（monkeypatch _resolve_binary，不依赖已安装 vep），并在已安装时做 --version 冒烟。

产出：
  <outdir>/variants.vcf        最小 VCF（annotate / filter 输入）
  <outdir>/vep_cache/          缓存目录占位
  <outdir>/homo_sapiens/       物种缓存子目录占位
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "variants.vcf").write_text(
        "##fileformat=VCFv4.2\n"
        "##contig=<ID=1,length=1000000>\n"
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
        "1\t100\t.\tA\tG\t50\tPASS\t.\n"
        "1\t200\t.\tC\tT\t60\tPASS\t.\n",
        encoding="utf-8",
    )
    cache = outdir / "vep_cache"
    (cache / "homo_sapiens").mkdir(parents=True, exist_ok=True)
    (cache / "homo_sapiens" / "README.placeholder").write_text(
        "# PLACEHOLDER: VEP 缓存（真实使用需 vep_install 下载）\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
