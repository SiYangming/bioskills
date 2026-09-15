#!/usr/bin/env python3
"""tmhmm native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict ../singalp/proteins_mature.fasta -o tmhmm.out
   python main.py plot proteins.fasta -o proteins.plot
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  predict  tmhmm [-mature] <fasta>          （结果默认写 stdout，可由 -o 重定向落盘）
  plot     tmhmm -plot <fasta>              （需 gnuplot/X11）
注意：TMHMM 2.0c 本体单线程，--threads 仅作统一接口与上层调度参考，不注入命令行。
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
    "predict": "跨膜螺旋预测：tmhmm [-mature] <fasta>（结果输出到 stdout，可 -o 落盘）",
    "plot": "跨膜拓扑图：tmhmm -plot <fasta>（需 gnuplot/X11）",
}


class TmhmmSkill(base.SkillBase):
    software = "tmhmm"
    binary = "tmhmm"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 tmhmm 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        if subcommand == "plot":
            cmd.append("-plot")
        elif kw.get("mature"):
            cmd.append("-mature")

        fasta = kw.get("fasta") or kw.get("input")
        if not fasta:
            raise ValueError(f"{subcommand} 缺少必填参数 fasta（输入蛋白质 FASTA）")
        cmd.append(str(fasta))

        # 线程：TMHMM 单线程，仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（tmhmm 默认写 stdout，由 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """tmhmm 公共选项。"""
    p.add_argument("input", nargs="?", help="输入蛋白质 FASTA（别名 --fasta）")
    p.add_argument("--fasta", help="输入蛋白质 FASTA 的别名")
    p.add_argument("-o", "--output", help="输出文件路径（默认写 stdout）")
    p.add_argument("--extra-args", help="透传给 tmhmm 的额外参数")


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（TMHMM 单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="tmhmm-skill",
        description="tmhmm native 技能驱动（TMHMM 2.0c 跨膜螺旋预测，许可受限需自备 tarball）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    _add_common_opts(pp)
    pp.add_argument("--mature", action="store_true", help="输入为已去信号肽的成熟序列（-mature）")
    _add_runtime_opts(pp)

    pt = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    _add_common_opts(pt)
    _add_runtime_opts(pt)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = TmhmmSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TmhmmSkill()
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

    # tmhmm 写 stdout：-o 指定时落盘，否则透传
    if getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
