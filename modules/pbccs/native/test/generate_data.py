#!/usr/bin/env python3
"""生成 pbccs native 测试用的合成输入。

注意：ccs 需要真实的 PacBio subreads BAM（pbbam 格式）才能产出 HiFi reads，
合成一个小型 subreads BAM 不现实。因此本脚本生成「文本占位 + 说明」，
run_test.sh 在无真实 subreads BAM / ccs 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」，不执行真实 ccs。

产出：
  <outdir>/subreads.bam  文本占位（内容说明需要真实 subreads BAM）
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
    placeholder = (
        "# PLACEHOLDER: pbccs/ccs 需要真实的 PacBio subreads BAM（pbbam 格式）才能运行。\n"
        "# 本文件仅用于测试命令构建/参数传递；真实运行请提供 *.subreads.bam。\n"
    )
    (outdir / "subreads.bam").write_text(placeholder, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
