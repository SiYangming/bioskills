#!/usr/bin/env python3
"""生成 iqtree native 测试用的合成输入。

IQ-TREE 建树需要序列变异信息；本脚本生成「结构合法的小蛋白比对」占位，
run_test.sh 对 ml/model 采用「python 构造 argv 验证命令构建不崩溃」的断言方式
（若系统已装 iqtree 仅做 --version 冒烟，不做真实建树以避免与 v2/v3 的 -nt/-T 差异冲突）。

产出：
  <outdir>/aln.phy    4 条 60 aa 蛋白序列的 PHYLIP 比对
  <outdir>/aln.fasta  等价 FASTA 比对
"""
from __future__ import annotations

import sys
from pathlib import Path

_SEQS = {
    "sp1": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLL",
    "sp2": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLL",
    "sp3": "MKTIIALSYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLM",
    "sp4": "MKTIIALTYIFCLVFADYKDDDDKGHHHHHHGGGGSSSSEEEETTTTAAAAVVVVLLLA",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    length = len(next(iter(_SEQS.values())))
    lines = [f"{len(_SEQS)} {length}"]
    for name, seq in _SEQS.items():
        lines.append(f"{name:<10}{seq}")
    (outdir / "aln.phy").write_text("\n".join(lines) + "\n", encoding="utf-8")

    (outdir / "aln.fasta").write_text(
        "".join(f">{name}\n{seq}\n" for name, seq in _SEQS.items()), encoding="utf-8"
    )

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
