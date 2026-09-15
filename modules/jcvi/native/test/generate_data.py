#!/usr/bin/env python3
"""生成 jcvi native 测试用的合成输入。

jcvi 各子命令读取的文本文件（anchors / seqids / layout / bed / blocks）都是纯文本，
本脚本生成最小可解析占位，供 run_test.sh 做 argv 构造验证（jcvi 未安装时不做真实计算/出图）。

产出：
  <outdir>/laame.plost.anchors   共线性锚点文件（dotplot 输入）
  <outdir>/seqids                染色体列表（karyotype 输入）
  <outdir>/layout                布局配置（karyotype/synteny 输入）
  <outdir>/laame.bed             物种 1 BED（synteny 输入）
  <outdir>/plost.bed             物种 2 BED（synteny 输入）
  <outdir>/blocks                共线性 blocks（synteny 输入）
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

    # anchors：两列基因对（jcvi comparo.catalog ortholog 产物格式）
    (outdir / "laame.plost.anchors").write_text(
        "laame_g1\tplost_g1\n"
        "laame_g2\tplost_g2\n"
        "laame_g3\tplost_g3\n",
        encoding="utf-8",
    )
    # seqids：每行一个 seqid（染色体）
    (outdir / "seqids").write_text("la1\npl1\n", encoding="utf-8")
    # layout：seqid,start,end,color,label（jcvi karyotype/synteny 布局行）
    (outdir / "layout").write_text(
        "la1,0,1,r,laame\n"
        "pl1,0,1,b,plost\n",
        encoding="utf-8",
    )
    (outdir / "laame.bed").write_text(
        "la1\t1000\t2000\tlaame_g1\t.\t+\n"
        "la1\t5000\t6000\tlaame_g2\t.\t+\n",
        encoding="utf-8",
    )
    (outdir / "plost.bed").write_text(
        "pl1\t1200\t2200\tplost_g1\t.\t+\n"
        "pl1\t5200\t6200\tplost_g2\t.\t+\n",
        encoding="utf-8",
    )
    # blocks：jcvi synteny 的共线性 blocks（.blocks / mcscan 输出风格）
    (outdir / "blocks").write_text(
        "la1\tlaame_g1\tla1\tlaame_g2\tpl1\tplost_g1\tpl1\tplost_g2\t+\t+\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据（anchors/seqids/layout/bed/blocks） -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
