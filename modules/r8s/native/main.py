#!/usr/bin/env python3
"""r8s 1.81 native 标准入口驱动。

r8s 以 NEXUS 文件（含 trees 块 + r8s 块的 divtime/fixage 指令）为输入，
命令行形如 `r8s -b -f r8s_in.txt`（-b 批处理、-f 指定输入）。

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run r8s_in.txt --threads 8
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

r8s 单线程；--threads 仅经 OMP_NUM_THREADS 透传（命令行不注入线程参数）。
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
    "run": "run：r8s -b -f <NEXUS 输入>（执行输入文件中的 divtime / crossv / chrono_description 指令）",
    "version": "version：r8s -v -b（打印版本并退出；r8s 以退出码 1 结束，属正常行为）",
}


class R8sSkill(base.SkillBase):
    software = "r8s"
    binary = "r8s"

    def _resolve_program(self) -> str:
        """惰性解析 r8s 二进制（测试可 monkeypatch）。"""
        path = shutil.which(self.binary)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'r8s'，请先安装：官方渠道无 conda/容器包，"
                "请用 native/install.sh 源码编译，或 brew tap brewsci/bio && brew install r8s，"
                "或构建 native/Dockerfile 自建容器。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令构建 r8s 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        # 线程提示：r8s 单线程，命令行不加线程参数；经 OMP_NUM_THREADS 透传。
        threads = self._effective_threads(subcommand, kw.get("threads"))
        self.env_vars["OMP_NUM_THREADS"] = str(threads)

        binary = self._resolve_program()

        if subcommand == "version":
            return [binary, "-v", "-b"]

        # subcommand == "run"
        input_file = kw.get("input")
        if not input_file:
            raise ValueError("run 缺少必填参数 input（NEXUS 输入文件）")
        cmd: list[str] = [binary, "-b", "-f", str(input_file)]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程 / 临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（经 OMP_NUM_THREADS 透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="r8s-skill",
        description="r8s 1.81 native 技能驱动（NEXUS 输入 + divtime 指令；自动注入 TMPDIR）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("input", nargs="?", help="NEXUS 输入文件（含 trees 块 + r8s 块）")
    pr.add_argument("-f", "--input", dest="input_opt", help="NEXUS 输入文件（与位置参数等价）")
    pr.add_argument("--extra-args", dest="extra_args", help="透传给 r8s 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pr)

    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = R8sSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = R8sSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    # input 位置参数 -> input；--input 别名
    if "input_opt" in kw:
        kw.setdefault("input", kw.pop("input_opt"))
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
