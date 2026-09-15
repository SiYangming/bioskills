#!/usr/bin/env python3
"""falcon native 标准入口驱动（FALCON / pb-falcon；PacBio 三代 OLC 组装）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run fc_run.cfg
   python main.py unzip fc_unzip.cfg --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（FALCON 由 INI 配置驱动，无 --threads 旗标；线程经 env NPROC 注入）：
  run    fc_run.py <fc_run.cfg>      # 主组装（overlap-layout-consensus）
  unzip  fc_unzip.py <fc_unzip.cfg>  # FALCON-Unzip 分型组装
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus，
经环境变量 NPROC 传递（对应 fc_run.cfg [job.defaults] NPROC）；临时目录经 TMPDIR 注入。
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
    "run": "FALCON 主组装（fc_run.py <fc_run.cfg>；fofn + INI 配置）",
    "unzip": "FALCON-Unzip 分型组装（fc_unzip.py <fc_unzip.cfg>）",
}

# 子命令 -> 真实可执行名
_BINARIES = {"run": "fc_run.py", "unzip": "fc_unzip.py"}


class FalconSkill(base.SkillBase):
    software = "falcon"
    binary = "fc_run.py"

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（fc_run.py / fc_unzip.py）。"""
        try:
            bin_name = _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 FALCON（mamba create -n pb-assembly "
                f"-c conda-forge -c bioconda pb-assembly 或 pb-falcon；见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 FALCON 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_sub_binary(subcommand)
        config = kw.get("config") or kw.get("input")
        if not config:
            raise ValueError(f"{subcommand} 缺少必填参数 config（FALCON INI 配置文件）")

        cmd: list[str] = [binary, str(config)]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令；线程经 env NPROC 注入，临时目录经 TMPDIR 注入。"""
        args = self.build_command(subcommand, **kwargs)
        env = dict(self.env_vars)
        env["NPROC"] = str(self._effective_threads(subcommand, kwargs.get("threads")))
        return base.run_command(args, env=env, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="falcon-skill",
        description="FALCON native 技能驱动（自动线程 NPROC / 临时目录 TMPDIR 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("config", nargs="?", help="FALCON 主流程 INI 配置（fc_run.cfg）")
    pr.add_argument("--config", dest="config_opt", help="配置文件别名")
    pr.add_argument("--extra-args", help="透传给 fc_run.py 的额外参数")
    _add_runtime_opts(pr)

    pu = sub.add_parser("unzip", help=SUBCOMMANDS["unzip"])
    pu.add_argument("config", nargs="?", help="FALCON-Unzip INI 配置（fc_unzip.cfg）")
    pu.add_argument("--config", dest="config_opt", help="配置文件别名")
    pu.add_argument("--extra-args", help="透传给 fc_unzip.py 的额外参数")
    _add_runtime_opts(pu)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（经 env NPROC 注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（经 env TMPDIR 注入）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = FalconSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FalconSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "config", "config_opt") and v is not None}
    kw["threads"] = ns.threads
    kw["config"] = ns.config_opt or ns.config

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
