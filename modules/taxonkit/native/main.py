#!/usr/bin/env python3
"""taxonkit native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py list --ids 4751 -j 8 -o sub.fungi.list
   python main.py lineage --data-dir ~/.taxonkit taxids.txt -n -r
   python main.py name2taxid names.txt -o name2taxid.tsv
   python main.py reformat lineage.tsv -f "{k};{p};{c};{o};{f};{g};{s}" -o taxonomy.tsv
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（NCBI Taxonomy，默认数据目录 ~/.taxonkit）：
  list       taxonkit list --ids <taxid> -j N [--indent ""] [-o out]
  lineage    taxonkit lineage [--data-dir DIR] <taxids.txt> [-n] [-r] [-o out]
  name2taxid taxonkit name2taxid [--data-dir DIR] <names.txt> -j N [-o out]
  reformat   taxonkit reformat [--data-dir DIR] -i <lineage.tsv> -f <fmt> [-o out]
所有子命令自动注入线程（-j，仅支持的工具使用）与环境变量优化。
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
    "list": "列出指定 TaxID 下的所有子单元（taxonkit list --ids <taxid>）",
    "lineage": "查询 TaxID 的谱系（taxonkit lineage）",
    "name2taxid": "物种名 -> TaxID 映射（taxonkit name2taxid）",
    "reformat": "把 lineage 结果格式化为多级分类（taxonkit reformat -f <fmt>）",
    "version": "打印 taxonkit 版本",
}

# 需要注入 -j 线程标志的子命令（taxonkit 仅 list / name2taxid 支持 -j）
_THREADED = {"list", "name2taxid"}


class TaxonkitSkill(base.SkillBase):
    software = "taxonkit"
    binary = "taxonkit"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 taxonkit 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        if subcommand == "version":
            return [binary, "version"]

        cmd: list[str] = [binary, subcommand]
        threads = self._effective_threads(subcommand, kw.get("threads"))
        data_dir = kw.get("data_dir")

        if subcommand == "list":
            ids = kw.get("ids")
            if not ids:
                raise ValueError("list 缺少必填参数 ids（--ids，如 4751）")
            cmd += ["--ids", str(ids)]
            if subcommand in _THREADED:
                cmd += ["-j", str(threads)]
            if kw.get("indent") is not None:
                cmd += ["--indent", str(kw["indent"])]
            if data_dir:
                cmd += ["--data-dir", str(data_dir)]
            if kw.get("json"):
                cmd.append("--json")
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        elif subcommand == "lineage":
            inp = kw.get("input")
            if not inp:
                raise ValueError("lineage 缺少必填参数 input（TaxID 列表文件）")
            cmd.append(str(inp))
            if kw.get("show_name"):
                cmd.append("-n")
            if kw.get("show_rank"):
                cmd.append("-r")
            if data_dir:
                cmd += ["--data-dir", str(data_dir)]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        elif subcommand == "name2taxid":
            inp = kw.get("input")
            if not inp:
                raise ValueError("name2taxid 缺少必填参数 input（物种名列表文件）")
            cmd.append(str(inp))
            if subcommand in _THREADED:
                cmd += ["-j", str(threads)]
            if data_dir:
                cmd += ["--data-dir", str(data_dir)]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        elif subcommand == "reformat":
            fmt = kw.get("format")
            if not fmt:
                raise ValueError("reformat 缺少必填参数 format（-f，如 \"{k};{p};{c};{o};{f};{g};{s}\"）")
            cmd += ["-f", str(fmt)]
            inp = kw.get("input")
            if inp:
                cmd += ["-i", str(inp)]
            if data_dir:
                cmd += ["--data-dir", str(data_dir)]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 交由 main() 输出）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="taxonkit-skill",
        description="taxonkit native 技能驱动（NCBI Taxonomy 处理，自动线程/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # list
    pl = sub.add_parser("list", help=SUBCOMMANDS["list"])
    pl.add_argument("--ids", required=True, help="根分类单元 TaxID（如真菌 4751，可逗号分隔）")
    pl.add_argument("--indent", help="缩进字符（默认两个空格；--indent '' 输出无缩进）")
    pl.add_argument("--data-dir", help="NCBI Taxonomy 数据目录（默认 ~/.taxonkit）")
    pl.add_argument("--json", action="store_true", help="输出 JSON 行格式")
    pl.add_argument("-o", "--output", help="输出文件（默认 stdout）")
    pl.add_argument("--extra-args", help="透传给 taxonkit list 的额外参数")
    _add_runtime_opts(pl)

    # lineage
    pn = sub.add_parser("lineage", help=SUBCOMMANDS["lineage"])
    pn.add_argument("input", help="TaxID 列表文件（每行一个 TaxID）")
    pn.add_argument("-n", "--show-name", action="store_true", help="附带分类名称")
    pn.add_argument("-r", "--show-rank", action="store_true", help="附带分类等级")
    pn.add_argument("--data-dir", help="NCBI Taxonomy 数据目录（默认 ~/.taxonkit）")
    pn.add_argument("-o", "--output", help="输出文件（默认 stdout）")
    pn.add_argument("--extra-args", help="透传给 taxonkit lineage 的额外参数")
    _add_runtime_opts(pn)

    # name2taxid
    p2 = sub.add_parser("name2taxid", help=SUBCOMMANDS["name2taxid"])
    p2.add_argument("input", help="物种名列表文件（每行一个名称）")
    p2.add_argument("--data-dir", help="NCBI Taxonomy 数据目录（默认 ~/.taxonkit）")
    p2.add_argument("-o", "--output", help="输出文件（默认 stdout）")
    p2.add_argument("--extra-args", help="透传给 taxonkit name2taxid 的额外参数")
    _add_runtime_opts(p2)

    # reformat
    pr = sub.add_parser("reformat", help=SUBCOMMANDS["reformat"])
    pr.add_argument("-f", "--format", required=True, help="输出格式模板，如 \"{k};{p};{c};{o};{f};{g};{s}\"")
    pr.add_argument("-i", "--input", help="lineage 结果文件（含 lineage 列）")
    pr.add_argument("--data-dir", help="NCBI Taxonomy 数据目录（默认 ~/.taxonkit）")
    pr.add_argument("-o", "--output", help="输出文件（默认 stdout）")
    pr.add_argument("--extra-args", help="透传给 taxonkit reformat 的额外参数")
    _add_runtime_opts(pr)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = TaxonkitSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TaxonkitSkill()
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
