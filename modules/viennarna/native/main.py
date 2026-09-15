#!/usr/bin/env python3
"""viennarna native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py rnafold pre_mirna.fa -p --noLP -T 37
   python main.py rnaeval structure.txt
   python main.py rnaplot structure.fa -t svg -o out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（ViennaRNA 2.x 命令行）：
  rnafold  RNAfold [-p] [--MEA] [--noLP] [-4] [-C] [-T <temp>] [--noPS] <input.fa>
  rnaeval  RNAeval [-4] [-C] [-T <temp>] <input>
  rnaplot  RNAplot [-t <format>] [-o <out>] <input>
ViennaRNA 主程序为单进程（部分程序 OpenMP 可选）；--threads 仅记录，不注入命令行。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "rnafold": "计算 RNA 二级结构 MFE / 配分函数（RNAfold）",
    "rnaeval": "评估给定结构的自由能（RNAeval）",
    "rnaplot": "绘制 RNA 二级结构图（RNAplot）",
}

# 子命令 -> 二进制名
_BINARY_BY_SUBCOMMAND = {
    "rnafold": "RNAfold",
    "rnaeval": "RNAeval",
    "rnaplot": "RNAplot",
}


class ViennarnaSkill(base.SkillBase):
    software = "viennarna"
    binary = "RNAfold"

    def _resolve_subcommand_binary(self, subcommand: str) -> str:
        self.binary = _BINARY_BY_SUBCOMMAND[subcommand]
        return self._resolve_binary()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 RNAfold / RNAeval / RNAplot 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_subcommand_binary(subcommand)
        cmd: list[str] = [binary]
        inp = kw.get("input")
        if not inp:
            raise ValueError(f"{subcommand} 缺少必填参数 input（输入文件）")

        if subcommand == "rnafold":
            if kw.get("partition"):
                cmd.append("-p")
            if kw.get("mea"):
                cmd.append("--MEA")
            if kw.get("no_lp"):
                cmd.append("--noLP")
            if kw.get("dna"):
                cmd.append("-4")
            if kw.get("constraint"):
                cmd.append("-C")
            if kw.get("temperature") is not None:
                cmd += ["-T", str(kw["temperature"])]
            if kw.get("no_guess"):
                cmd.append("--noPS")
            cmd.append(str(inp))

        elif subcommand == "rnaeval":
            if kw.get("dna"):
                cmd.append("-4")
            if kw.get("constraint"):
                cmd.append("-C")
            if kw.get("temperature") is not None:
                cmd += ["-T", str(kw["temperature"])]
            cmd.append(str(inp))

        elif subcommand == "rnaplot":
            if kw.get("plot_format"):
                cmd += ["-t", str(kw["plot_format"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd.append(str(inp))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="viennarna-skill",
        description="ViennaRNA native 技能驱动（RNA 二级结构预测与比较）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # rnafold
    pf = sub.add_parser("rnafold", help=SUBCOMMANDS["rnafold"])
    pf.add_argument("input", help="输入 RNA/转录本 FASTA")
    pf.add_argument("-p", "--partition", action="store_true", help="计算配分函数与碱基配对概率")
    pf.add_argument("--MEA", dest="mea", action="store_true", help="计算 MEA 结构")
    pf.add_argument("--noLP", dest="no_lp", action="store_true", help="禁止孤立碱基对")
    pf.add_argument("-4", "--dna", dest="dna", action="store_true", help="输入按 DNA 处理")
    pf.add_argument("-C", "--constraint", action="store_true", help="使用序列中的约束注释")
    pf.add_argument("-T", "--temperature", type=float, help="折叠温度（默认 37）")
    pf.add_argument("--noPS", dest="no_guess", action="store_true", help="不输出 PostScript 结构图")
    pf.add_argument("--extra-args", help="透传给 RNAfold 的额外参数")
    _add_runtime_opts(pf)

    # rnaeval
    pe = sub.add_parser("rnaeval", help=SUBCOMMANDS["rnaeval"])
    pe.add_argument("input", help="含结构注释的序列文件")
    pe.add_argument("-4", "--dna", dest="dna", action="store_true", help="输入按 DNA 处理")
    pe.add_argument("-C", "--constraint", action="store_true", help="使用序列中的约束注释")
    pe.add_argument("-T", "--temperature", type=float, help="评估温度（默认 37）")
    pe.add_argument("--extra-args", help="透传给 RNAeval 的额外参数")
    _add_runtime_opts(pe)

    # rnaplot
    pp = sub.add_parser("rnaplot", help=SUBCOMMANDS["rnaplot"])
    pp.add_argument("input", help="结构文件（序列 + 点括号结构）")
    pp.add_argument("-t", "--plot-format", dest="plot_format", help="输出图形格式（ps/eps/svg/xrna）")
    pp.add_argument("-o", "--output", help="输出文件")
    pp.add_argument("--extra-args", help="透传给 RNAplot 的额外参数")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（ViennaRNA 单进程，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = ViennarnaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ViennarnaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
