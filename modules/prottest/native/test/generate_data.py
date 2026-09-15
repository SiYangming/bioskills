#!/usr/bin/env python3
"""生成 prottest native 测试用的合成输入。

ProtTest3 的模型选择计算量极大（14.md 记 ~1472 分钟），合成数据无法覆盖真实计算；
因此本脚本只生成「结构合法的氨基酸比对 + 起始树」占位，run_test.sh 退化为
「python 构造 argv 验证命令构建不崩溃」的断言方式（真实执行需用户自行提供比对）。

产出：
  <outdir>/aln.fasta   3 条短蛋白序列的 FASTA 比对
  <outdir>/aln.phy     PHYLIP 格式比对（ProTest 亦接受）
  <outdir>/tree.nwk    最小 Newick 起始树（-t 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path

# 3 条等长短蛋白序列（30 aa）
_SEQS = {
    "sp1": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHH",
    "sp2": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHH",
    "sp3": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHN",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    # FASTA
    (outdir / "aln.fasta").write_text(
        "".join(f">{name}\n{seq}\n" for name, seq in _SEQS.items()), encoding="utf-8"
    )

    # PHYLIP（严格格式：名称 10 列 + 序列）
    length = len(next(iter(_SEQS.values())))
    lines = [f"{len(_SEQS)} {length}"]
    for name, seq in _SEQS.items():
        lines.append(f"{name:<10}{seq}")
    (outdir / "aln.phy").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 最小 Newick 起始树
    (outdir / "tree.nwk").write_text("((sp1,sp2),sp3);\n", encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
