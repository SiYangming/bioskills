#!/usr/bin/env python3
"""生成 pathview native 测试用合成数据。

pathview 需要真实 KEGG kgml + 通路映射才能出图，合成数据无法覆盖真实可视化计算。
因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv 验证命令构建
不崩溃（monkeypatch _resolve_binary，不依赖已安装 R/pathview）。

产出（<outdir> 下，均为 Tab 分隔）：
  study.ko.txt   基因数据表（首列 gene id，次列 log2FC 数值）
  cpd.txt        化合物数据表（首列 compound id，次列数值）
  ko_pathways.txt  通路 id 清单（逗号分隔，供 --kegg-ids 参考）
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

    (outdir / "study.ko.txt").write_text(
        "K00001\t1.50\n"
        "K00002\t-2.10\n"
        "K00003\t0.30\n"
        "K00004\t-0.75\n",
        encoding="utf-8",
    )
    (outdir / "cpd.txt").write_text(
        "C00001\t2.00\n"
        "C00002\t-1.25\n",
        encoding="utf-8",
    )
    (outdir / "ko_pathways.txt").write_text(
        "ko00010,ko00020\n", encoding="utf-8"
    )
    print(f"已生成 pathview 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
