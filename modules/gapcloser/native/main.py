#!/usr/bin/env python3
"""gapcloser native 标准入口驱动（GapCloser v1.12-r6；SOAPdenovo2 套件补洞工具）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py fill -a genome.fa -b config.txt -o gapcloser.fa -l 120 -t 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  fill  GapCloser -a <scaffold> -b <config> -o <out> -l <max_read_len> -p <overlap> -t <threads>
参数语义取自 GapCloser 二进制内建 help（strings 提取）：
  -a scaffold file（required）· -b config file · -o output file
  -l max read len · -p overlap para（<=31，default=25）· -t thread num
所有子命令自动注入线程（-t）与临时目录优化。
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
    "fill": "闭合 scaffold 中的 N gap（GapCloser -a <scaffold> -b <config> -o <out> -l <max_read_len> -p <overlap> -t <threads>）",
}


class GapcloserSkill(base.SkillBase):
    software = "gapcloser"
    binary = "GapCloser"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 GapCloser 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        scaffold = kw.get("scaffold") or kw.get("input")
        config = kw.get("config")
        if not scaffold:
            raise ValueError("fill 缺少必填参数 scaffold（-a 输入 scaffold FASTA）")
        if not config:
            raise ValueError("fill 缺少必填参数 config（-b SOAPdenovo 式文库配置）")

        out = kw.get("output") or "gapcloser.fa"
        cmd: list[str] = [
            binary,
            "-a", str(scaffold),
            "-b", str(config),
            "-o", str(out),
            "-l", str(int(kw.get("max_read_len") or 120)),
            "-p", str(int(kw.get("overlap") or 25)),
            "-t", str(threads),
        ]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gapcloser-skill",
        description="GapCloser native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pf = sub.add_parser("fill", help=SUBCOMMANDS["fill"])
    pf.add_argument("scaffold", nargs="?", help="输入 scaffold FASTA（别名 --scaffold / -a）")
    pf.add_argument("-a", "--scaffold", dest="scaffold_opt", help="输入 scaffold FASTA 的别名")
    pf.add_argument("-b", "--config", required=True, help="SOAPdenovo 式文库配置文件")
    pf.add_argument("-o", "--output", help="输出补洞 FASTA（默认 gapcloser.fa）")
    pf.add_argument("-l", "--max-read-len", type=int, help="最大读长（默认 120）")
    pf.add_argument("-p", "--overlap", type=int, help="overlap 参数 13–31（默认 25）")
    pf.add_argument("--extra-args", help="透传给 GapCloser 的额外参数")
    _add_runtime_opts(pf)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（GapCloser -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GapcloserSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GapcloserSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "scaffold", "scaffold_opt") and v is not None}
    kw["threads"] = ns.threads
    kw["scaffold"] = ns.scaffold_opt or ns.scaffold

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    result = base.run_command(cmd, env=skill.env_vars, check=False)
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
