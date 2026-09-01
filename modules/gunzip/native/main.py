#!/usr/bin/env python3
"""gunzip native 标准入口驱动。

命令逻辑迁移自 snakemake.smk/isoseq.smk/workflow/modules/gunzip/snakemake/local/gunzip.smk：
  gzip -cd <in.gz> > <out>

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py gunzip genome.fa.gz -o genome.fa
   python main.py gunzip reads.fq.gz
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

运行前提：PATH 中可解析 gzip（Debian bookworm 1.12 / macOS 系统 gzip 均可）。
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
    "gunzip": "解压 .gz 文件（gzip -cd <in.gz> > <out>）",
}


class GunzipSkill(base.SkillBase):
    software = "gunzip"
    binary = "gzip"  # gunzip 是 gzip 的硬链接前端；统一走 gzip -cd

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建命令行。"""
        if subcommand != "gunzip":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()

        archive = kw.get("input")
        if not archive:
            raise RuntimeError("gunzip 需要输入 .gz 文件（input）")
        archive = str(archive)
        if not archive.endswith(".gz"):
            raise RuntimeError("gunzip 子命令要求输入以 .gz 结尾的文件")

        out = kw.get("output") or archive[:-3]
        args = str(kw.get("args") or "").strip()

        # gzip -cd <in.gz> > <out>；bash -o pipefail 保证 gzip 失败时整体报错
        script = f"gzip -cd {args} {shlex.quote(archive)} > {shlex.quote(out)}"
        return ["bash", "-o", "pipefail", "-c", script]


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gunzip-skill",
        description="gunzip native 技能驱动（gzip -cd <in.gz> > <out>）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pg = sub.add_parser("gunzip", help=SUBCOMMANDS["gunzip"])
    pg.add_argument("input", help="输入 .gz 文件")
    pg.add_argument("-o", "--output", help="输出文件（默认去掉 .gz 后缀）")
    pg.add_argument("--args", default="", help="透传 gzip 附加参数（可选）")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（gzip -cd 单线程，仅供调度器参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _query_version(bin_name: str) -> str:
    try:
        return subprocess.run(
            f"{bin_name} --version 2>&1",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        ).stdout.strip().splitlines()[0] or "n/a"
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
        skill = GunzipSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GunzipSkill()
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

    # 版本文件（与 nf-core/gunzip 的 versions.yml 对齐）
    try:
        out = ns.output or ns.input[:-3]
        outdir = Path(out).parent
        outdir.mkdir(parents=True, exist_ok=True)
        with open(outdir / "versions.yml", "w") as fh:
            fh.write(f"gunzip:\n    gunzip: {_query_version('gzip')}\n")
    except Exception as exc:
        print(f"[WARN] 写 versions.yml 失败: {exc}", file=sys.stderr)

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
