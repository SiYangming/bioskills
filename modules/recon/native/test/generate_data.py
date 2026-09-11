#!/usr/bin/env python3
"""生成 recon native 测试用的合成 MSP 与序列名清单。

产出（<outdir> 下）：
  seqnames    序列名清单（首行计数，其后按字典序排列的序列名）
  recon.msps  合成 MSP 文件（每行一条局部比对：
              score %iden q_start q_end q_name s_start s_end s_name）

设计：两条「重复家族」各 3 个拷贝，分别位于不同序列的不同坐标，拷贝间两两给出
全长 MSP。RECON 四阶段据此可稳定聚出 2 个家族（每个 3 个元素），用于 run_test.sh
的最小真跑链路断言。数据由固定模板生成（无随机），可重复断言。

说明：MSP 格式与 RECON 官方示例 examples/dmel-lib.msps 一致（上游 RECON 1.10）。
"""
from __future__ import annotations

import sys
from pathlib import Path

# (家族名, 拷贝长度 bp, 相似度 %, [(序列名, 起点), ...])
FAMILIES = [
    ("famA", 500, 99.0, [("Chr1", 10000), ("Chr2", 20000), ("Chr3", 30000)]),
    ("famB", 300, 97.5, [("Chr1", 50000), ("Chr2", 60000), ("Chr4", 70000)]),
]

_WIDTH = 8  # 坐标零填充宽度（对齐上游示例）


def build_msp_lines() -> list[str]:
    """把两条家族的拷贝两两配成 MSP 行。"""
    lines: list[str] = []
    for fidx, (_name, length, iden, copies) in enumerate(FAMILIES):
        for i in range(len(copies)):
            for j in range(i + 1, len(copies)):
                qname, qstart = copies[i]
                sname, sstart = copies[j]
                qend = qstart + length
                send = sstart + length
                score = int(length * 2 * iden / 100) + fidx  # 家族内近似、家族间轻微区分
                lines.append(
                    f"{score:06d} {iden:5.1f} "
                    f"{qstart:0{_WIDTH}d} {qend:0{_WIDTH}d} {qname} "
                    f"{sstart:0{_WIDTH}d} {send:0{_WIDTH}d} {sname}"
                )
    return lines


def build_seqnames() -> list[str]:
    """收集全部出现过的序列名，按字典序排序。"""
    names = sorted({name for _n, _l, _i, copies in FAMILIES for name, _s in copies})
    return names


def write_seqnames(path: Path, names: list[str]) -> None:
    with open(path, "w") as fh:
        fh.write(f"{len(names)}\n")
        for name in names:
            fh.write(f"{name}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    names = build_seqnames()
    write_seqnames(outdir / "seqnames", names)
    lines = build_msp_lines()
    (outdir / "recon.msps").write_text("\n".join(lines) + "\n")

    print(f"已生成测试数据 -> {outdir}（{len(names)} 条序列，{len(lines)} 条 MSP，"
          f"{len(FAMILIES)} 个预期同源家族）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
