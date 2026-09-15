#!/usr/bin/env python3
"""gblocks native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py extract sample.aln -t p
   python main.py extract sample.aln -t c -o sample.aln-gb
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  extract  Gblocks <aln> -t=<c|p|d> [-e=-gaps] [-b1..-b5 [args]]
           （Gblocks 原生把结果写到 <aln>-gb；-o 时由驱动改名搬运）
  version  Gblocks --help（打印用法/版本）
Gblocks 是单线程经典工具，--threads 仅作统一接口保留（不注入命令行）。
"""

from __future__ import annotations

import argparse
import json
import shutil
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
    "extract": "多序列比对 -> 保守区块比对（Gblocks <aln> -t=<c|p|d>，原生输出 <aln>-gb）",
    "version": "打印 Gblocks 用法/版本（Gblocks --help）",
}


class GblocksSkill(base.SkillBase):
    software = "gblocks"
    binary = "Gblocks"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        Gblocks 为单线程工具，本值仅用于统一接口/日志，不注入命令行。
        """
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def native_output(self, alignment: str) -> str:
        """Gblocks 原生把结果写到 <输入>-gb。"""
        return f"{alignment}-gb"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 Gblocks 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()

        if subcommand == "version":
            return [binary, "--help"]

        alignment = kw.get("input") or kw.get("aln")
        if not alignment:
            raise ValueError("extract 缺少必填参数 input（多序列比对文件）")

        cmd: list[str] = [binary, str(alignment)]
        aln_type = kw.get("aln_type") or "p"
        cmd.append(f"-t={aln_type}")
        if kw.get("allow_gaps"):
            cmd.append("-e=-gaps")
        # -b1..-b4 数值型；-b5 为 n/h/a 策略
        for i in range(1, 6):
            val = kw.get(f"b{i}")
            if val is not None:
                cmd.append(f"-b{i}={val}")

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr；extract 失败不抛，交由 main 判定）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gblocks-skill",
        description="gblocks native 技能驱动（保守区块提取；单线程经典工具）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # extract
    pe = sub.add_parser("extract", help=SUBCOMMANDS["extract"])
    pe.add_argument("input", help="输入多序列比对（FASTA/PIR/NBRF）")
    pe.add_argument("-t", "--aln-type", choices=["c", "p", "d"], default="p",
                    help="序列类型：c（codon）/ p（protein）/ d（DNA），默认 p")
    pe.add_argument("-o", "--output", help="输出保守区块比对路径（缺省 <input>-gb）")
    pe.add_argument("-e", "--allow-gaps", dest="allow_gaps", action="store_true",
                    help="允许半位点含空位（-e=-gaps）")
    pe.add_argument("--b1", type=int, help="-b1 最小保守区块长度（默认 10）")
    pe.add_argument("--b2", type=int, help="-b2 侧翼位置阈值（默认 8）")
    pe.add_argument("--b3", type=int, help="-b3 最大连续非保守位置数（默认 10）")
    pe.add_argument("--b4", type=int, help="-b4 区块内最小空位位置数（默认 4）")
    pe.add_argument("--b5", choices=["n", "h", "a"], help="-b5 空位位置策略（默认 h）")
    pe.add_argument("--extra-args", help="透传给 Gblocks 的额外参数")
    _add_runtime_opts(pe)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（Gblocks 单线程，仅接口保留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = GblocksSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GblocksSkill()
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

    # extract：Gblocks 原生写 <input>-gb；若指定 -o 则改名搬运
    if ns.subcommand == "extract" and getattr(ns, "output", None):
        src = Path(skill.native_output(ns.input))
        if src.exists() and str(src) != str(ns.output):
            shutil.move(str(src), ns.output)

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
