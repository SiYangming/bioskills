#!/usr/bin/env python3
"""cafe native 标准入口驱动。

CAFE v4.2.1 以「命令脚本」方式运行：脚本首行 shebang 指向 cafe 可执行文件，脚本体依次为
version/date/load/tree/lambda/report 等命令（即官方 cafe_command）。caferror.py 则读取同一
脚本（-i），以迭代误差模型并行运行。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py command --gene-table orthomcl2cafe.tab --tree '(((laame:191.8,plost:191.8)...));' -o cafe_command
   python main.py run --command-file cafe_command
   python main.py caferror --command-file cafe_command --tmp-dir caferror_1
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  command   生成 CAFE 命令脚本（shebang=<cafe> + load -i <tab> -t <threads> -p <pvalue> + tree + lambda -s + report）
  run       cafe <command_script>           单次 CAFE 分析（等效直接执行 shebang 脚本）
  caferror  caferror.py -i <command_script> 迭代误差模型并行运行（推荐）
线程写入生成脚本的 load -t（优先级：--threads > per_subcommand_threads > default_cpus）。
"""

from __future__ import annotations

import argparse
import json
import os
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
    "command": "生成 CAFE 命令脚本（shebang=cafe 路径；load -t <threads> -p <pvalue> + tree + lambda -s + report）",
    "run": "执行 CAFE 命令脚本（cafe <script>；等效 shebang 脚本方式）",
    "caferror": "以 caferror.py 迭代误差模型并行运行（caferror.py -i <script>）",
}

DEFAULT_PVALUE = 0.01
DEFAULT_REPORT = "out"


class CafeSkill(base.SkillBase):
    software = "cafe"
    binary = "cafe"

    # -- 二进制/脚本惰性解析（测试可 monkeypatch） --------------------------- #
    def _resolve_tool(self, name: str) -> str:
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 cafe。"
            )
        return path

    def _resolve_caferror(self) -> str:
        return self._resolve_tool("caferror.py")

    # -- CAFE 命令脚本生成 ------------------------------------------------- #
    def write_command_script(self, *, gene_table: str | None, tree: str | None,
                             output: str | None = None, pvalue: float | None = None,
                             report: str | None = None, threads: int | None = None) -> str:
        """生成 CAFE 命令脚本（写入 output 或 tmpdir）并返回脚本路径。"""
        if not gene_table or not tree:
            raise ValueError("生成 CAFE 命令脚本需要 --gene-table 与 --tree（Newick 字符串）")
        try:
            cafe = self._resolve_binary()
        except RuntimeError:
            # cafe 未安装时仍可生成脚本（shebang 走 env，运行时由 PATH 解析）
            cafe = "/usr/bin/env cafe"
        n_threads = int(threads) if threads else self._effective_threads("command", None)
        pv = DEFAULT_PVALUE if pvalue is None else float(pvalue)
        rep = report or DEFAULT_REPORT
        if output:
            out = Path(output)
        else:
            out = Path(self.make_tmpdir("cafe_")) / "cafe_command"
        out.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            f"#!{cafe}",
            "version",
            "date",
            "",
            f"load -i {gene_table} -t {n_threads} -p {pv}",
            f"tree {tree}",
            "lambda -s",
            f"report {rep}",
        ]
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        os.chmod(out, 0o755)
        return str(out)

    # -- 命令行构建 --------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        if subcommand == "command":
            raise ValueError("command 子命令由 main() 特殊处理（仅生成脚本，不执行）")

        threads = self._effective_threads(subcommand, kw.get("threads"))
        script = kw.get("command_file")
        if not script:
            script = self.write_command_script(
                gene_table=kw.get("gene_table"), tree=kw.get("tree"),
                output=kw.get("output") or kw.get("script_out"),
                pvalue=kw.get("pvalue"), report=kw.get("report"), threads=threads,
            )

        if subcommand == "run":
            return [self._resolve_binary(), str(script)]

        # caferror
        cmd: list[str] = [self._resolve_caferror(), "-i", str(script)]
        if kw.get("tmp_dir"):
            cmd += ["-d", str(kw["tmp_dir"])]
        if kw.get("err_output"):
            cmd += ["-o", str(kw["err_output"])]
        if kw.get("verbose"):
            cmd += ["-v", "1"]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_generation_opts(p: argparse.ArgumentParser, *, require_table_tree: bool) -> None:
    """command/run/caferror 共用的脚本生成参数。"""
    req = require_table_tree
    p.add_argument("--gene-table", required=req, help="基因家族大小表（如 orthomcl2cafe.tab）")
    p.add_argument("--tree", required=req, help="带枝长的 Newick 树字符串（含分号）")
    p.add_argument("-p", "--pvalue", type=float, default=DEFAULT_PVALUE, help="家族显著性 p 值阈值（默认 0.01）")
    p.add_argument("--report", default=DEFAULT_REPORT, help="报告前缀（默认 out）")


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（写入生成脚本 load -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="cafe-skill",
        description="cafe native 技能驱动（CAFE v4.2.1 命令脚本 + caferror.py 迭代误差模型）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # command（仅生成脚本）
    pc = sub.add_parser("command", help=SUBCOMMANDS["command"])
    _add_generation_opts(pc, require_table_tree=True)
    pc.add_argument("-o", "--output", required=True, help="生成的 CAFE 命令脚本路径")
    _add_runtime_opts(pc)

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    _add_generation_opts(pr, require_table_tree=False)
    pr.add_argument("--command-file", help="既有 CAFE 命令脚本（与 --gene-table/--tree 二选一）")
    pr.add_argument("-o", "--output", help="生成的命令脚本路径（缺省写入 tmpdir）")
    _add_runtime_opts(pr)

    # caferror
    pe = sub.add_parser("caferror", help=SUBCOMMANDS["caferror"])
    _add_generation_opts(pe, require_table_tree=False)
    pe.add_argument("--command-file", help="既有 CAFE 命令脚本（与 --gene-table/--tree 二选一）")
    pe.add_argument("--script-out", help="生成的命令脚本路径（缺省写入 tmpdir）")
    pe.add_argument("-d", "--tmp-dir", help="caferror.py 工作目录（默认 caferror_X）")
    pe.add_argument("--err-output", help="caferror.py 误差输出文件（-o）")
    pe.add_argument("--verbose", action="store_true", help="caferror.py 详细输出（-v 1）")
    _add_runtime_opts(pe)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = CafeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CafeSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    # command：仅生成脚本，不执行
    if ns.subcommand == "command":
        try:
            script = skill.write_command_script(
                gene_table=ns.gene_table, tree=ns.tree, output=ns.output,
                pvalue=ns.pvalue, report=ns.report, threads=ns.threads,
            )
        except (RuntimeError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        print(script)
        return 0

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
