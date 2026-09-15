#!/usr/bin/env python3
"""edena native 标准入口驱动（Edena V3.131028；说明型）。

⚠️ DEPRECATED：本模块登记的是 Edena（String Graph 基因组组装，Edena V3.131028，
论文 Hernandez et al. 2008）。官网 genomic.ch 页面已功能性损坏，V3.131028 后长期停更
——基因组组装请改用 SPAdes / Velvet / Canu 等现代工具。

本驱动为「说明型 + 命令构造」：不实际运行 edena 二进制（软件已淘汰、官网损坏），
按官方用法构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. assemble：reads → contigs
   edena -nThreads <N> -DRpairs <reads1> <reads2> [-p <prefix>]      # PE
   edena -nThreads <N> <reads1> [-p <prefix>]                        # SE
2. overlap：导出重叠信息 / 按阈值重跑
   edena -e <out.ovl> -overlapCutoff <N> -p <out_N>

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble --reads1 fragment.1.fastq --reads2 fragment.2.fastq --threads 4
   python main.py overlap --overlap-out out.ovl --overlap-cutoff 70 --prefix out_70
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 Edena（edena 在 PATH，bioconda edena=3.131028，见 README「环境安装」）。
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
    "assemble": "reads → contigs（edena -nThreads N -DRpairs r1 r2；String Graph 组装）",
    "overlap": "重叠信息导出/阈值重跑（edena -e out.ovl -overlapCutoff N -p out_N）",
}

DEPRECATED_NOTE = (
    "⚠️ Edena 已淘汰（Edena V3.131028 后停更，genomic.ch 官网页面损坏，建议用 "
    "SPAdes / Velvet / Canu 替代）：本模块仅作历史参考登记，以下命令构造仅供复现历史"
    "分析，新项目请勿使用。"
)


class EdenaSkill(base.SkillBase):
    software = "edena"
    binary = "edena"

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """assemble / overlap：构造（不执行）历史 Edena 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        bin_path = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "assemble":
            reads1 = kw.get("reads1")
            if not reads1:
                raise RuntimeError("assemble 需要 --reads1（读段文件，SE 或 PE read1）")
            cmd = [bin_path, "-nThreads", str(threads)]
            reads2 = kw.get("reads2")
            if reads2 and kw.get("drpairs", True):
                cmd += ["-DRpairs", self._abspath(reads1), self._abspath(reads2)]
            else:
                cmd.append(self._abspath(reads1))
            if kw.get("prefix"):
                cmd += ["-p", str(kw["prefix"])]
            return cmd

        # overlap
        overlap_out = kw.get("overlap_out")
        cutoff = kw.get("overlap_cutoff")
        if not overlap_out:
            raise RuntimeError("overlap 需要 --overlap-out（-e 重叠信息输出文件）")
        if cutoff is None:
            raise RuntimeError("overlap 需要 --overlap-cutoff（-overlapCutoff 阈值，如 50-90）")
        cmd = [bin_path, "-e", self._abspath(overlap_out),
               "-overlapCutoff", str(int(cutoff))]
        if kw.get("prefix"):
            cmd += ["-p", str(kw["prefix"])]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="edena-skill",
        description="Edena native 技能驱动（说明型：构造历史 edena 命令，已废弃，"
                    "仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("--reads1", required=True, help="读段文件（SE 或 PE read1，FASTQ）")
    pa.add_argument("--reads2", help="PE read2（提供则构造 -DRpairs <r1> <r2>）")
    pa.add_argument("--no-drpairs", dest="drpairs", action="store_false",
                    help="关闭 -DRpairs（即使提供了 --reads2）")
    pa.add_argument("-p", "--prefix", help="输出前缀（产物 <prefix>_contigs.fasta）")
    _add_runtime_opts(pa)

    po = sub.add_parser("overlap", help=SUBCOMMANDS["overlap"])
    po.add_argument("-e", "--overlap-out", required=True, help="重叠信息输出文件（如 out.ovl）")
    po.add_argument("--overlap-cutoff", type=int, required=True,
                    help="重叠阈值（-overlapCutoff，文档示例 50-90）")
    po.add_argument("-p", "--prefix", help="输出前缀（如 out_70）")
    _add_runtime_opts(po)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（-nThreads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = EdenaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EdenaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "assemble":
        print("[hint] Edena 组装产物为 <prefix>_contigs.fasta（未指定 -p 时用默认前缀）",
              file=sys.stderr)
    if ns.subcommand == "overlap":
        print("[hint] -overlapCutoff 常见扫描区间 50-90（步长 10），再人工挑选最优结果",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
