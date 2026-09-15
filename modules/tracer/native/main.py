#!/usr/bin/env python3
"""tracer native 标准入口驱动。

Tracer v1.7.1 是 BEAST/MrBayes/LAMARC 等贝叶斯 MCMC 运行结果的轨迹（trace）分析工具，
以 Java GUI 形态分发（lib/tracer.jar）；官方 `tracer` 启动器即 `java -Xms64m -Xmx10000m -jar
lib/tracer.jar "$@"`（见官方 release 包 bin/tracer）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run beast.log beast2.log
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  run   tracer <log> [<log2> ...]    启动 GUI 载入一个或多个 MCMC trace/日志文件
说明：Tracer 为交互式 GUI，不产出文件；每个子命令接受 --threads/--tmpdir 仅为接口统一，
      JVM 内存/调优通过 JAVA_OPTS 环境变量透传。
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
    "run": "启动 Tracer GUI 并载入一个或多个 MCMC 日志/trace 文件",
}


class TracerSkill(base.SkillBase):
    software = "tracer"
    binary = "tracer"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令构建 tracer 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        if subcommand == "run":
            logs = kw.get("logs")
            if logs:
                if isinstance(logs, str):
                    cmd.append(logs)
                else:
                    cmd.extend(str(x) for x in logs)

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
        prog="tracer-skill",
        description="tracer native 技能驱动（Java GUI；JVM 调优走 JAVA_OPTS）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("logs", nargs="*", help="一个或多个 MCMC 日志/trace 文件")
    pr.add_argument("--extra-args", help="透传给 tracer 启动器的额外参数")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（Tracer 为 GUI，仅为接口统一）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = TracerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TracerSkill()
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
