#!/usr/bin/env python3
"""生成 cafe native 测试用的合成输入。

CAFE 需要「基因家族大小表」（orthomcl2cafe.tab 风格）与带枝长的 Newick 树。
本脚本生成最小可解析数据；run_test.sh 以 argv 构造 + 生成的命令脚本内容做断言
（cafe 二进制未安装时不做真实分析）。

产出：
  <outdir>/orthomcl2cafe.tab   基因家族大小表（Desc + Family ID + 各物种拷贝数）
  <outdir>/tree.nwk            带枝长的 Newick 树（含分号）
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

    # CAFE 输入表：首列 Desc，第二列 Family ID，其后为各物种拷贝数
    table = (
        "Desc\tFamily ID\tlaame\tplost\tparub\tsccit\n"
        "(null)\t1\t5\t6\t7\t8\n"
        "(null)\t2\t12\t10\t11\t9\n"
        "(null)\t3\t3\t2\t4\t3\n"
        "(null)\t4\t20\t18\t19\t21\n"
    )
    (outdir / "orthomcl2cafe.tab").write_text(table, encoding="utf-8")
    (outdir / "tree.nwk").write_text(
        "(((laame:191.8242,plost:191.8242):44.9287,"
        "(parub:107.055,sccit:107.055):129.6979):13.6525);\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据（基因家族表 + Newick 树） -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
