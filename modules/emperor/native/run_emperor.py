#!/usr/bin/env python3
"""Emperor PCoA 交互式可视化驱动（native/main.py 的后端）。

读取 ordination（skbio OrdinationResults 文本格式，如 QIIME 2 core-metrics 导出的
`*_pcoa_results` 经 `qiime tools export` 后的 ordination.txt）+ 样本元数据表，
调用 emperor.core.Emperor 渲染交互式 HTML，并在输出目录写入 Emperor 支持文件。

用法（一般由 native/main.py plot 子命令调用）：
  python3 run_emperor.py --ordination ordination.txt --metadata sample-metadata.tsv \
      --output emperor.html [--custom-axis <col> ...] [--dimensions 5] \
      [--ignore-missing-samples] [--remote]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="run_emperor.py",
        description="Emperor PCoA 交互式可视化驱动（emperor.core.Emperor）",
    )
    p.add_argument("--ordination", required=True, help="排序结果文件（skbio OrdinationResults 文本格式）")
    p.add_argument("--metadata", required=True, help="样本元数据表（Tab 分隔，首列样本 ID）")
    p.add_argument("--output", required=True, help="输出 HTML 文件路径")
    p.add_argument("--custom-axis", action="append", default=[], dest="custom_axes",
                   help="自定义轴元数据列（可多次给出）")
    p.add_argument("--dimensions", type=int, default=5, help="保留的排序维度数（默认 5）")
    p.add_argument("--ignore-missing-samples", action="store_true",
                   help="缺元数据的样本改为填充占位值（默认报错）")
    p.add_argument("--remote", action="store_true", help="使用远程 CDN 资源（默认本地随包资源）")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        import pandas as pd
        from skbio.stats.ordination import OrdinationResults
        from emperor import Emperor
    except ImportError as exc:  # pragma: no cover - 环境缺失时给出清晰提示
        print(
            f"[ERROR] 缺少依赖: {exc}。请先安装 emperor（pip install emperor==1.0.5 "
            f"或 mamba create -n <env> -c conda-forge emperor=1.0.5）。",
            file=sys.stderr,
        )
        return 1

    ordination = OrdinationResults.read(args.ordination)
    mapping = pd.read_csv(args.metadata, sep="\t", index_col=0, comment=None, dtype=str)
    mapping.index = mapping.index.astype(str)

    emperor = Emperor(
        ordination,
        mapping,
        dimensions=args.dimensions,
        remote=args.remote,
        ignore_missing_samples=args.ignore_missing_samples,
    )
    if args.custom_axes:
        emperor.custom_axes = list(args.custom_axes)

    html = emperor.make_emperor(standalone=True)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")

    # 复制 Emperor 静态支持文件到输出目录（支持离线打开）
    try:
        emperor.copy_support_files(target=str(out_path.parent))
    except Exception as exc:  # pragma: no cover - 支持文件缺失时不影响主产物
        print(f"[WARN] 复制 Emperor 支持文件失败: {exc}", file=sys.stderr)

    print(f"EMPEROR_OK {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
