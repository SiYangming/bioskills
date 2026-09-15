#!/usr/bin/env python3
"""生成 emperor native 测试用的合成输入。

Emperor 的交互式渲染依赖 skbio/scikit-bio 解析真实 ordination，合成数据无法覆盖真实渲染，
因此本脚本生成「最小 PCoA ordination + 元数据表」，run_test.sh 在 emperor 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/ordination.txt        skbio OrdinationResults 文本格式（3 样本 × 2 轴）
  <outdir>/sample-metadata.tsv   样本元数据表（首列样本 ID，与 ordination 样本匹配）
"""
from __future__ import annotations

import sys
from pathlib import Path

# skbio OrdinationResults 文本格式（Eigvals/Proportion explained/Species/Site/Biplot/Site constraints）
_ORDINATION = """Eigvals\t2.0\t1.5
Proportion explained\t0.5\t0.375
Species\t0
Site\t3\t2
S1\t0.10\t0.20
S2\t0.30\t0.10
S3\t-0.20\t-0.10
Biplot\t0
Site constraints\t0
"""

_METADATA = """#SampleID\tSubject\tBodySite\tDaysSinceExperimentStart
S1\tA\tgut\t1
S2\tB\tgut\t3
S3\tA\tgut\t7
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "ordination.txt").write_text(_ORDINATION, encoding="utf-8")
    (outdir / "sample-metadata.tsv").write_text(_METADATA, encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
