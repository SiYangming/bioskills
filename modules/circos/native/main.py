#!/usr/bin/env python3
"""circos native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py plot -conf circos.conf -outputdir out -noparanoid
   python main.py modules
   python main.py gddiag
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  plot     circos -noparanoid -conf <circos.conf> [-outputdir <dir>]
  modules  circos -modules           # 检查 Perl 依赖模块是否齐全
  gddiag   gddiag                    # GD 渲染诊断（生成 gddiag.png）
Circos 为单进程 Perl 渲染，--threads 仅作契约字段保留（不注入二进制）。
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
    "plot": "依 circos.conf 渲染环形图（circos -conf）",
    "modules": "检查 Circos 依赖的 Perl 模块（circos -modules）",
    "gddiag": "GD 渲染依赖诊断（gddiag）",
}

# 子命令 -> 实际调用的可执行文件
SUBCOMMAND_BINARY = {
    "plot": "circos",
    "modules": "circos",
    "gddiag": "gddiag",
}


class CircosSkill(base.SkillBase):
    software = "circos"
    binary = "circos"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（Circos 不并行，仅契约）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_tool(self, name: str) -> str:
        """惰性解析指定可执行文件路径（测试可 monkeypatch）。"""
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 circos。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 circos / gddiag 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        tool = SUBCOMMAND_BINARY[subcommand]
        binary = self._resolve_tool(tool)

        if subcommand == "plot":
            conf = kw.get("conf") or kw.get("input")
            if not conf:
                raise ValueError("plot 缺少必填参数 conf（circos.conf 路径）")
            cmd: list[str] = [binary]
            if kw.get("noparanoid", True):
                cmd.append("-noparanoid")
            cmd += ["-conf", str(conf)]
            outputdir = kw.get("outputdir")
            if outputdir:
                cmd += ["-outputdir", str(outputdir)]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        # modules / gddiag
        cmd = [binary]
        if subcommand == "modules":
            cmd.append("-modules")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="circos-skill",
        description="circos native 技能驱动（环形图渲染 / 依赖检查）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # plot
    pp = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    pp.add_argument("input", nargs="?", help="主配置文件（别名 --conf）")
    pp.add_argument("--conf", help="主配置文件 circos.conf 的别名")
    pp.add_argument("-o", "--outputdir", help="输出目录")
    pp.add_argument("--no-noparanoid", dest="noparanoid", action="store_false",
                    help="开启 paranoid 校验（默认 -noparanoid）")
    pp.add_argument("--extra-args", help="透传给 circos 的额外参数")
    _add_runtime_opts(pp)

    # modules
    pm = sub.add_parser("modules", help=SUBCOMMANDS["modules"])
    pm.add_argument("--extra-args", help="透传给 circos 的额外参数")
    _add_runtime_opts(pm)

    # gddiag
    pg = sub.add_parser("gddiag", help=SUBCOMMANDS["gddiag"])
    pg.add_argument("--extra-args", help="透传给 gddiag 的额外参数")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（Circos 不并行，仅契约）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = CircosSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CircosSkill()
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
