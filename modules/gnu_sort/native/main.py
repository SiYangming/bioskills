#!/usr/bin/env python3
"""gnu_sort native 标准入口驱动。

命令逻辑迁移自 snakemake.smk/isoseq.smk/workflow/modules/gnu_sort/snakemake/gnu_sort.smk：
  sort [args] <in> > <out.sorted>

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py sort genes.gtf --args "-k1,1 -k4,4n" -o genes.sorted.gtf
   python main.py sort reads.sam
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

运行前提：PATH 中可解析 sort（Debian bookworm coreutils 9.1 / macOS BSD sort 均可；
--parallel 线程注入仅在检测到 GNU coreutils 时启用）。
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
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
    "sort": "文本行排序（sort [args] <in> > <out>.sorted，支持 --args 透传）",
}


class GnuSortSkill(base.SkillBase):
    software = "gnu_sort"
    binary = "sort"

    _is_gnu: bool | None = None  # 缓存 sort --version 探测结果

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _detect_gnu(self) -> bool:
        if self._is_gnu is None:
            try:
                ver = subprocess.run(
                    ["sort", "--version"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    check=False,
                ).stdout
                self._is_gnu = "GNU coreutils" in ver
            except Exception:
                self._is_gnu = False
        return self._is_gnu

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建命令行。"""
        if subcommand != "sort":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()

        inp = kw.get("input")
        if not inp:
            raise RuntimeError("sort 需要输入文件（input）")
        inp = str(inp)
        out = kw.get("output") or f"{inp}.sorted"
        args = str(kw.get("args") or "").strip()

        # GNU 专属 --parallel 线程注入（BSD sort 无此选项；用户 args 里已含 parallel 则不注入）
        threads = self._effective_threads(subcommand, kw.get("threads"))
        if self._detect_gnu() and threads > 1 and "parallel" not in args:
            args = (args + f" --parallel={threads}").strip()

        # sort [args] <in> > <out>；bash -o pipefail 保证 sort 失败时整体报错
        script = f"{shlex.quote(binary)} {args} {shlex.quote(inp)} > {shlex.quote(out)}"
        return ["bash", "-o", "pipefail", "-c", script]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gnu-sort-skill",
        description="gnu_sort native 技能驱动（sort [args] <in> > <out>.sorted）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    ps = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    ps.add_argument("input", help="输入文件（文本/SAM/GTF 等）")
    ps.add_argument("-o", "--output", help="输出文件（默认 <input>.sorted）")
    ps.add_argument("--args", default="", help="透传 sort 附加参数（如 -k1,1 -k4,4n、-n、-S 2G、--parallel 8）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（GNU sort 注入 --parallel；BSD 忽略）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _query_version() -> str:
    try:
        return subprocess.run(
            "sort --version 2>&1 | head -n1",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        ).stdout.strip() or "n/a"
    except Exception:
        return "n/a"


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GnuSortSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GnuSortSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # 版本文件（与 nf-core/gnu/sort 的 versions.yml 对齐）
    try:
        out = ns.output or f"{ns.input}.sorted"
        outdir = Path(out).parent
        outdir.mkdir(parents=True, exist_ok=True)
        with open(outdir / "versions.yml", "w") as fh:
            fh.write(f"GNU_SORT:\n    coreutils: {_query_version()}\n")
    except Exception as exc:
        print(f"[WARN] 写 versions.yml 失败: {exc}", file=sys.stderr)

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
