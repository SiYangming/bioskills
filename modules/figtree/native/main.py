#!/usr/bin/env python3
"""figtree native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py export tree_fullName.RAxML out.pdf -graphic PDF
   python main.py export tree.tre out.png -graphic PNG -width 320 -height 320
   python main.py view tree_fullName.RAxML          # 打开交互式 GUI（需显示环境）
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  export  java <JAVA_OPTS> -Djava.awt.headless=true -jar figtree.jar -graphic <PDF|SVG|PNG|JPEG> [-width <i>] [-height <i>] [-url] <tree-file> <graphic-file>
  view    java <JAVA_OPTS> -jar figtree.jar [-url] <tree-file>
JVM 堆内存与临时目录经 JAVA_OPTS（optimization.env_vars，含 {tmpdir} 占位）透传；FigTree 单进程，
--threads 仅作统一接口与上层调度参考，不注入命令行。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
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
    "export": "无界面导出出版级图片：java -jar figtree.jar -graphic <PDF|SVG|PNG|JPEG> <tree> <out>",
    "view": "打开交互式 GUI（java -jar figtree.jar <tree>；需 X11/显示环境）",
}

GRAPHIC_FORMATS = ("PDF", "SVG", "PNG", "JPEG")


class FigtreeSkill(base.SkillBase):
    software = "figtree"
    binary = "java"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _java_prefix(self, headless: bool = False) -> list[str]:
        """java 可执行 + JAVA_OPTS（-Xmx / -Djava.io.tmpdir）+（可选）headless 组成的命令前缀。"""
        java = self._resolve_binary()
        opts = shlex.split(self.env_vars.get("JAVA_OPTS", ""))
        prefix = [java, *opts]
        if headless:
            prefix.append("-Djava.awt.headless=true")
        prefix.append("-jar")
        return prefix

    def _resolve_jar(self) -> str:
        """解析 figtree.jar：优先 $FIGTREE_JAR / $FIGTREE_HOME，其次常见安装位置。"""
        cands: list[Path] = []
        explicit = os.environ.get("FIGTREE_JAR")
        if explicit:
            cands.append(Path(explicit))
        home = os.environ.get("FIGTREE_HOME")
        if home:
            cands += [Path(home) / "lib" / "figtree.jar", Path(home) / "figtree.jar"]
        cands += [
            Path.home() / "software" / "FigTree_v1.4.4" / "lib" / "figtree.jar",
            Path.home() / "software" / "figtree" / "lib" / "figtree.jar",
            Path("/opt/FigTree_v1.4.4/lib/figtree.jar"),
            Path("/opt/figtree/lib/figtree.jar"),
        ]
        for cand in cands:
            if cand.is_file():
                return str(cand)
        raise RuntimeError(
            "未找到 figtree.jar；请设置 FIGTREE_JAR / FIGTREE_HOME，或安装到 "
            "~/software/FigTree_v1.4.4/lib/figtree.jar。官方下载："
            "http://tree.bio.ed.ac.uk/software/figtree/"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 java -jar figtree.jar 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        tree = kw.get("input")
        if not tree:
            raise ValueError("缺少必填参数 input（输入树文件 Newick/NEXUS/NHX）")

        # FigTree 单进程，仅解析线程优先级（统一接口），不注入命令行
        self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "export":
            fmt = str(kw.get("graphic") or "PDF").upper()
            if fmt not in GRAPHIC_FORMATS:
                raise ValueError(f"-graphic 格式非法（可选: {', '.join(GRAPHIC_FORMATS)}）")
            out = kw.get("output")
            if not out:
                raise ValueError("export 缺少必填参数 output（输出图片文件）")
            cmd = self._java_prefix(headless=True)
            cmd.append(self._resolve_jar())
            cmd += ["-graphic", fmt]
            if kw.get("width") is not None:
                cmd += ["-width", str(kw["width"])]
            if kw.get("height") is not None:
                cmd += ["-height", str(kw["height"])]
            if kw.get("url"):
                cmd.append("-url")
            cmd += [str(tree), str(out)]
        else:  # view
            cmd = self._java_prefix(headless=False)
            cmd.append(self._resolve_jar())
            if kw.get("url"):
                cmd.append("-url")
            cmd.append(str(tree))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（FigTree 单进程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 JAVA_OPTS -Djava.io.tmpdir）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="figtree-skill",
        description="figtree native 技能驱动（系统发育树可视化/导出；JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pe = sub.add_parser("export", help=SUBCOMMANDS["export"])
    pe.add_argument("input", help="输入树文件（Newick/NEXUS/NHX）")
    pe.add_argument("output", help="输出图片文件（如 out.pdf/out.png）")
    pe.add_argument("-graphic", "--graphic", default="PDF",
                    help="图形格式：PDF|SVG|PNG|JPEG（默认 PDF）")
    pe.add_argument("-width", "--width", type=int, help="图形宽度（像素）")
    pe.add_argument("-height", "--height", type=int, help="图形高度（像素）")
    pe.add_argument("--url", action="store_true", help="输入文件按 URL 读取")
    pe.add_argument("--extra-args", help="透传给 FigTree 的额外参数")
    _add_runtime_opts(pe)

    pv = sub.add_parser("view", help=SUBCOMMANDS["view"])
    pv.add_argument("input", help="输入树文件（Newick/NEXUS/NHX）")
    pv.add_argument("--url", action="store_true", help="输入文件按 URL 读取")
    pv.add_argument("--extra-args", help="透传给 FigTree 的额外参数")
    _add_runtime_opts(pv)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = FigtreeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FigtreeSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars = skill._render_env_vars(
            (skill.meta.get("optimization", {}) or {}).get("env_vars", {})
        )

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
