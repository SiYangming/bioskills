#!/usr/bin/env python3
"""beagle-lib（BEAGLE 3.1.2）native 标准入口驱动。

BEAGLE 本身是系统发育似然计算**库**（libhmsbeagle），不是可执行程序：
上游（BEAST/BEAST2/MrBayes）通过头文件与共享库链接，并借 pkg-config 元数据
（`hmsbeagle-1`）获取编译/链接参数，运行期由 LD_LIBRARY_PATH 定位 .so。

本驱动提供库的安装/校验类子命令：
1. CLI 直跑（人类 / Shell）：
   python main.py install --prefix ~/software/beagle-lib-3.1.2 --source-dir ./beagle-lib-3.1.2 --threads 8
   python main.py verify  --prefix ~/software/beagle-lib-3.1.2
   python main.py flags   --prefix ~/software/beagle-lib-3.1.2
2. Agent Function Calling / Schema 自省：--schema / --list-commands

环境变量（供 BEAST2 等上层工具链接库）：
   PKG_CONFIG_PATH=<prefix>/lib/pkgconfig
   LD_LIBRARY_PATH=<prefix>/lib
   C_INCLUDE_PATH=<prefix>/include
"""
from __future__ import annotations

import argparse
import json
import os
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
    "install": "install：源码编译安装 BEAGLE 库到 --prefix（./autogen.sh && ./configure --prefix=... && make && make install）",
    "verify": "verify：用 pkg-config 校验已安装库版本（pkg-config --modversion hmsbeagle-1）",
    "flags": "flags：打印下游工具链接 BEAGLE 所需参数（pkg-config --cflags --libs hmsbeagle-1）",
}

# 与 meta.yaml inputs.prefix 默认值对齐
DEFAULT_PREFIX = "~/software/beagle-lib-3.1.2"
PKG_NAME = "hmsbeagle-1"


class BeagleLibSkill(base.SkillBase):
    software = "beagle-lib"
    binary = "pkg-config"

    def __init__(self, meta_path: str | Path | None = None):
        super().__init__(meta_path)
        self.prefix = os.path.expanduser(DEFAULT_PREFIX)
        self._apply_prefix(self.prefix)

    def _apply_prefix(self, prefix: str) -> None:
        """按安装前缀设置 pkg-config / 动态库 / 头文件搜索路径。"""
        self.prefix = os.path.expanduser(prefix)
        self.env_vars["PKG_CONFIG_PATH"] = f"{self.prefix}/lib/pkgconfig"
        self.env_vars["LD_LIBRARY_PATH"] = f"{self.prefix}/lib"
        self.env_vars["C_INCLUDE_PATH"] = f"{self.prefix}/include"

    def _resolve_pkg_config(self) -> str:
        """惰性解析 pkg-config（测试可 monkeypatch）。"""
        path = shutil.which("pkg-config")
        if not path:
            raise RuntimeError(
                "未找到 pkg-config；请先安装（Debian: apt install pkg-config；conda: pkg-config）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        # —— verify / flags：单条 pkg-config 命令 ——
        if subcommand in ("verify", "flags"):
            pkg = self._resolve_pkg_config()
            if subcommand == "verify":
                return [pkg, "--modversion", PKG_NAME]
            return [pkg, "--cflags", "--libs", PKG_NAME]

        # —— install：多步源码构建，包成一条 bash -lc（make -j 用线程数） ——
        threads = self._effective_threads(subcommand, kw.get("threads"))
        prefix = os.path.expanduser(str(kw.get("prefix") or self.prefix))
        src = str(kw.get("source_dir") or ".")
        extra = str(kw.get("extra_args") or "").strip()
        script = (
            f'cd "{src}" && ./autogen.sh && ./configure --prefix="{prefix}"'
            + (f" {extra}" if extra else "")
            + f" && make -j {threads} && make install"
        )
        return ["bash", "-lc", script]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（install 注入 make -j N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="beagle-lib-skill",
        description="beagle-lib（BEAGLE 3.1.2）native 技能驱动（库：install/verify/flags 子命令）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pi = sub.add_parser("install", help=SUBCOMMANDS["install"])
    pi.add_argument("--prefix", help="安装前缀（默认 ~/software/beagle-lib-3.1.2）")
    pi.add_argument("--source-dir", dest="source_dir", help="源码目录（默认当前目录）")
    pi.add_argument("--extra-args", dest="extra_args", help="透传给 ./configure（如 --enable-sse）")
    _add_runtime_opts(pi)

    pv = sub.add_parser("verify", help=SUBCOMMANDS["verify"])
    pv.add_argument("--prefix", help="安装前缀（用于设置 PKG_CONFIG_PATH）")
    _add_runtime_opts(pv)

    pf = sub.add_parser("flags", help=SUBCOMMANDS["flags"])
    pf.add_argument("--prefix", help="安装前缀（用于设置 PKG_CONFIG_PATH）")
    _add_runtime_opts(pf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = BeagleLibSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BeagleLibSkill()
    if getattr(ns, "prefix", None):
        skill._apply_prefix(ns.prefix)
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

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
