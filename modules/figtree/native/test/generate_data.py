#!/usr/bin/env python3
"""生成 figtree native 测试用的合成输入。

FigTree 的可视化/导出依赖图形栈，且 jar 未必安装；因此本脚本只生成「结构合法的树文件」，
run_test.sh 对 export/view 采用「python 构造 argv 验证命令构建不崩溃」的断言方式。

产出：
  <outdir>/tree.nwk    4 taxa 的 Newick 树（带节点标签，模拟 RAxML bipartitions）
  <outdir>/tree.nex    等价 NEXUS 树（FigTree 亦接受）
"""
from __future__ import annotations

import sys
from pathlib import Path

_NEWICK = "((sp1:0.1,sp2:0.2)90:0.3,(sp3:0.15,sp4:0.25)80:0.4);\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "tree.nwk").write_text(_NEWICK, encoding="utf-8")
    (outdir / "tree.nex").write_text(
        "#NEXUS\nBEGIN TREES;\n  TREE tree1 = " + _NEWICK + "END;\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
