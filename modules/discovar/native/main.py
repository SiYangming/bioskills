#!/usr/bin/env python3
"""discovar native 标准入口驱动（DISCOVAR / DISCOVAR de novo 52488；说明型）。

⚠️ DEPRECATED：本模块登记的是 Broad Institute 的 DISCOVAR / DISCOVAR de novo
（版本 52488；Weisenfeld et al. 2014）。Broad 已停止维护，官网页面功能性损坏、
旧 FTP 下载不可用——基因组组装/变异请改用 GATK / SPAdes / Canu 等现代工具。

本驱动为「说明型 + 命令构造」：不实际运行 DISCOVAR 二进制（软件已淘汰、官方下载失效），
按官方 KEY=VALUE 用法构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. DiscovarDeNovo：de novo 组装
   DiscovarDeNovo READS=<in.bam> OUT_DIR=<dir> NUM_THREADS=<N> [REFHEAD=<ref>]
2. Discovar：有参考区域组装 / variant calling
   Discovar READS=<in.bam> OUT_HEAD=<head> REGIONS=<chr:start-end> TMP=<tmp> [REFERENCE=<fa>]
3. PrepareDiscovarGenome：预生成参考
   PrepareDiscovarGenome REF=<genome.fasta>
4. NhoodInfo：组装邻域信息可视化
   NhoodInfo OUT=<out> DIR_IN=<a.final/> SEEDS=<chr:pos> COUNT=True SHOW_INV=True

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py discovardenovo --reads sample-reads.bam --out-dir asm --threads 4
   python main.py discovar --reads sample-reads.bam --out-head asm/genome \
       --regions 10:30892106-30933760 --tmp asm/tmp
   python main.py prepare --ref sample-genome.fasta
   python main.py nhoodinfo --out out --dir-in asm/a.final --seeds 10:30.5M
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 DISCOVAR（程序在 PATH，bioconda discovar=52488 / discovardenovo=52488，
见 README「环境安装」）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "discovardenovo": "无参考从头组装（DiscovarDeNovo READS= OUT_DIR= NUM_THREADS=）",
    "discovar": "有参考区域组装 / variant calling（Discovar READS= OUT_HEAD= REGIONS= TMP=）",
    "prepare": "预生成参考（PrepareDiscovarGenome REF=，生成 <ref>.m100，耗时）",
    "nhoodinfo": "组装邻域信息可视化（NhoodInfo OUT= DIR_IN= SEEDS=）",
}

# 子命令 → 真实可执行名
_BINARIES = {
    "discovardenovo": "DiscovarDeNovo",
    "discovar": "Discovar",
    "prepare": "PrepareDiscovarGenome",
    "nhoodinfo": "NhoodInfo",
}

DEPRECATED_NOTE = (
    "⚠️ DISCOVAR / DISCOVAR de novo 已淘汰（Broad 停止维护，52488 为末版，官网页面损坏，"
    "建议用 GATK / SPAdes / Canu 替代）：本模块仅作历史参考登记，以下命令构造仅供复现"
    "历史分析，新项目请勿使用。"
)


class DiscovarSkill(base.SkillBase):
    software = "discovar"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件，找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 DISCOVAR 并把其目录加入 PATH"
                f"（mamba create -n discovar-native -c conda-forge -c bioconda "
                f"discovar=52488 或 discovardenovo=52488；见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    @staticmethod
    def _b(value) -> str:
        return "True" if value else "False"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """discovardenovo / discovar / prepare / nhoodinfo：构造（不执行）命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "discovardenovo":
            reads = kw.get("reads")
            out_dir = kw.get("out_dir")
            if not reads:
                raise RuntimeError("discovardenovo 需要 --reads（READS= 输入 BAM）")
            if not out_dir:
                raise RuntimeError("discovardenovo 需要 --out-dir（OUT_DIR= 输出目录）")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd = [bin_path, f"READS={self._abspath(reads)}",
                   f"OUT_DIR={self._abspath(out_dir)}", f"NUM_THREADS={threads}"]
            if kw.get("refhead"):
                cmd.append(f"REFHEAD={kw['refhead']}")
            return cmd

        if subcommand == "discovar":
            reads = kw.get("reads")
            out_head = kw.get("out_head")
            regions = kw.get("regions")
            if not reads:
                raise RuntimeError("discovar 需要 --reads（READS= 输入 BAM）")
            if not out_head:
                raise RuntimeError("discovar 需要 --out-head（OUT_HEAD= 输出前缀）")
            if not regions:
                raise RuntimeError("discovar 需要 --regions（REGIONS= 如 10:30892106-30933760）")
            tmp = kw.get("tmp") or self.tmpdir
            cmd = [bin_path, f"READS={self._abspath(reads)}",
                   f"OUT_HEAD={self._abspath(out_head)}", f"REGIONS={regions}",
                   f"TMP={self._abspath(tmp)}"]
            if kw.get("reference"):
                cmd.append(f"REFERENCE={self._abspath(kw['reference'])}")
            return cmd

        if subcommand == "prepare":
            ref = kw.get("ref")
            if not ref:
                raise RuntimeError("prepare 需要 --ref（REF= 参考基因组 FASTA）")
            return [bin_path, f"REF={self._abspath(ref)}"]

        # nhoodinfo
        out = kw.get("out")
        dir_in = kw.get("dir_in")
        if not out:
            raise RuntimeError("nhoodinfo 需要 --out（OUT= 输出前缀）")
        if not dir_in:
            raise RuntimeError("nhoodinfo 需要 --dir-in（DIR_IN= 输入目录，如 a.final/）")
        cmd = [bin_path, f"OUT={kw['out']}", f"DIR_IN={self._abspath(dir_in)}"]
        if kw.get("seeds"):
            cmd.append(f"SEEDS={kw['seeds']}")
        cmd.append(f"COUNT={self._b(kw.get('count', True))}")
        cmd.append(f"SHOW_INV={self._b(kw.get('show_inv', True))}")
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="discovar-skill",
        description="DISCOVAR / DISCOVAR de novo native 技能驱动（说明型：构造历史 "
                    "KEY=VALUE 命令，已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pd = sub.add_parser("discovardenovo", help=SUBCOMMANDS["discovardenovo"])
    pd.add_argument("--reads", required=True, help="READS= 输入 BAM")
    pd.add_argument("--out-dir", required=True, help="OUT_DIR= 输出目录")
    pd.add_argument("--refhead", help="REFHEAD= 参考基因组名（有参考组装时提供）")
    _add_runtime_opts(pd)

    pc = sub.add_parser("discovar", help=SUBCOMMANDS["discovar"])
    pc.add_argument("--reads", required=True, help="READS= 输入 BAM")
    pc.add_argument("--out-head", required=True, help="OUT_HEAD= 输出前缀")
    pc.add_argument("--regions", required=True, help="REGIONS= 区域（chr:start-end）")
    pc.add_argument("--tmp", help="TMP= 临时目录（默认取 self.tmpdir）")
    pc.add_argument("--reference", help="REFERENCE= 参考 FASTA（variant calling）")
    _add_runtime_opts(pc)

    pp = sub.add_parser("prepare", help=SUBCOMMANDS["prepare"])
    pp.add_argument("--ref", required=True, help="REF= 参考基因组 FASTA")
    _add_runtime_opts(pp)

    pn = sub.add_parser("nhoodinfo", help=SUBCOMMANDS["nhoodinfo"])
    pn.add_argument("--out", required=True, help="OUT= 输出前缀（生成 <out>.dot）")
    pn.add_argument("--dir-in", required=True, help="DIR_IN= 输入目录（如 a.final/）")
    pn.add_argument("--seeds", help="SEEDS= 种子区域（如 10:30.5M）")
    pn.add_argument("--no-count", dest="count", action="store_false", help="COUNT=False")
    pn.add_argument("--no-show-inv", dest="show_inv", action="store_false",
                    help="SHOW_INV=False")
    _add_runtime_opts(pn)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（discovardenovo NUM_THREADS=）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if args and args[0] == "--":
        args = args[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = DiscovarSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = DiscovarSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "prepare":
        print("[hint] PrepareDiscovarGenome 生成 <ref>.m100 非常耗时", file=sys.stderr)
    if ns.subcommand == "nhoodinfo":
        print("[hint] 产物 <out>.dot 可 dot -Tsvg <out>.dot -o <out>.svg 转图",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
