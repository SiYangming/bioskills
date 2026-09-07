#!/usr/bin/env python3
"""生成 ncbi-datasets-cli native 测试用的占位输入。

datasets download/summary 需联网访问 NCBI 且真实下载基因组不可行，因此本脚本
只生成「文本占位 + 说明」，run_test.sh 退化为「python 构造 argv 验证命令构建
不崩溃 + --list-commands/--schema/help 自省 + install.sh bash -n 语法检查」；
若宿主机 PATH 中已有 datasets 二进制，则额外做 datasets --version 冒烟。

产出：
  <outdir>/accessions.txt   真实示例 accession（供人工核对；测试仅作占位）
  <outdir>/README.txt       说明：为何不做真实下载回归
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

    (outdir / "accessions.txt").write_text(
        "GCF_000001405.39   # 人类 GRCh38.p14 参考基因组（NCBI 官方示例）\n"
        "GCF_000009045.1    # 大肠杆菌 str. K-12 substr. MG1655（小基因组快速测试）\n",
        encoding="utf-8",
    )
    (outdir / "README.txt").write_text(
        "PLACEHOLDER: datasets download/summary 需要联网访问 NCBI，真实下载基因组不可行；\n"
        "本模块测试退化为 argv 构造验证 + 自省（--list-commands/--schema/help）+ install.sh bash -n。\n"
        "人工验证命令：\n"
        "  datasets download genome accession GCF_000001405.39 --include genome,gff3 -o ncbi_dataset.zip\n"
        "  datasets summary genome taxon 'Homo sapiens' --as-json-lines\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
