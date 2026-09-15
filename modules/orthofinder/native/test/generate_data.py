#!/usr/bin/env python3
"""生成 orthofinder native 测试用的合成输入。

OrthoFinder 全流程需要真实蛋白组与联网/比对依赖，合成数据无法覆盖真实计算；因此本脚本
只生成「结构正确的多物种蛋白 FASTA 目录」，run_test.sh 用 python 构造 argv 验证命令构建
（monkeypatch 二进制解析），不实际运行 OrthoFinder。

产出：
  <outdir>/input_proteins/<species>.fasta   每物种一个蛋白 FASTA（文件名即物种名）
  <outdir>/prev_results/                    上次结果目录占位（resume 的 -b 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    proteins = outdir / "input_proteins"
    proteins.mkdir(parents=True, exist_ok=True)

    (proteins / "speciesA.fasta").write_text(
        ">spA_g1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">spA_g2\nMSTAGKVIKCKAAVLWEEKKPFSIEEVEVAPPK\n",
        encoding="utf-8",
    )
    (proteins / "speciesB.fasta").write_text(
        ">spB_g1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">spB_g2\nMSTAGKVIKCKAAVLWEEKKPFSIEEVEVAPPA\n",
        encoding="utf-8",
    )
    (proteins / "speciesC.fasta").write_text(
        ">spC_g1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVA\n",
        encoding="utf-8",
    )
    (outdir / "prev_results").mkdir(exist_ok=True)
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
