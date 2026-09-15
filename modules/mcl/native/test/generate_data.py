#!/usr/bin/env python3
"""生成 mcl native 测试用的合成输入。

MCL 聚类需要真实加权图才能产出有意义结果，合成数据无法覆盖真实计算；因此本脚本
只生成「结构正确的小型 ABC 图 + 标签文件」，run_test.sh 在 mcl 未安装时用 python
构造 argv 验证命令构建（monkeypatch 二进制解析），不实际运行 mcl。

产出：
  <outdir>/graph.abc     最小 ABC 格式图（每行：标签A 标签B 权重）
  <outdir>/graph.mci     占位原生矩阵文件（dump 子命令输入）
  <outdir>/labels.txt    索引 -> 标签映射（mcxdump -tab 输入）
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

    # 最小 ABC 图：两簇 a/b/c 与 d/e/f，外加一条跨簇弱边
    (outdir / "graph.abc").write_text(
        "a\tb\t0.9\n"
        "b\tc\t0.8\n"
        "a\tc\t0.7\n"
        "d\te\t0.9\n"
        "e\tf\t0.85\n"
        "d\tf\t0.75\n"
        "c\td\t0.10\n",
        encoding="utf-8",
    )
    (outdir / "graph.mci").write_text(
        "1 2 0.9\n2 3 0.8\n", encoding="utf-8"
    )
    (outdir / "labels.txt").write_text(
        "a\nb\nc\nd\ne\nf\n", encoding="utf-8"
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
