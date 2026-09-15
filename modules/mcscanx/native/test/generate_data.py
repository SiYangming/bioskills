#!/usr/bin/env python3
"""生成 mcscanx native 测试用的合成输入。

MCScanX 读取「输入前缀」对应的 <prefix>.blast（m8 比对）与 <prefix>.gff（基因位置）。
本脚本生成最小可解析数据；run_test.sh 以 argv 构造做断言（mcscanx 未安装时不做真实检测）。

产出：
  <outdir>/input.gff          基因位置文件（chr/start/end/gene）
  <outdir>/input.blast        BLAST m8 比对（12 列）
  <outdir>/control            绘图控制文件（染色体大小 + 各物种染色体列表）
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

    # 基因位置：chr  start  end  gene（chrome 用两位物种前缀 + 染色体号）
    gff = (
        "la1\t1000\t2000\tlaame_g1\n"
        "la1\t5000\t6000\tlaame_g2\n"
        "la1\t9000\t10000\tlaame_g3\n"
        "pl1\t1200\t2200\tplost_g1\n"
        "pl1\t5200\t6200\tplost_g2\n"
        "pl1\t9200\t10200\tplost_g3\n"
    )
    (outdir / "input.gff").write_text(gff, encoding="utf-8")

    # BLAST m8（query subject identity length mismatch gapopen qstart qend sstart send evalue bitscore）
    blast = (
        "laame_g1\tplost_g1\t85.0\t300\t10\t2\t1\t300\t1\t300\t1e-50\t600\n"
        "laame_g2\tplost_g2\t80.0\t280\t12\t3\t1\t280\t1\t280\t1e-45\t560\n"
        "laame_g3\tplost_g3\t82.0\t290\t11\t2\t1\t290\t1\t290\t1e-48\t580\n"
    )
    (outdir / "input.blast").write_text(blast, encoding="utf-8")

    # control：首行两条染色体大小，随后两行各物种染色体列表（逗号分隔）
    (outdir / "control").write_text("600\n800\nla1\npl1\n", encoding="utf-8")
    print(f"已生成测试数据（input.gff + input.blast + control） -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
