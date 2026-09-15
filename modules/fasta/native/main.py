#!/usr/bin/env python3
"""fasta native 标准入口驱动。

FASTA（上游仓库/程序名 fasta36）序列搜索/比对工具包的自包含驱动，覆盖 7 个核心程序：
  search     fasta36    <query> <library>      （蛋白/核酸相似性搜索，启发式）
  ssearch    ssearch36  <query> <library>      （Smith-Waterman 全 DP 搜索）
  fastx      fastx36    <query> <library>      （翻译后核酸查蛋白库）
  fasty      fasty36    <query> <library>      （允许移码的翻译搜索）
  ggsearch   ggsearch36 <query> <library>      （全全局比对搜索）
  glsearch   glsearch36 <query> <library>      （半全局比对搜索）
  lalign     lalign36  <query> <library>       （多个局部比对）

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py search query.fasta db.fasta -m 8 -E 1e-5 -o hits.tsv
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程说明：FASTA 各搜索程序均为单线程；子命令仍接受 --threads/--tmpdir 以保持接口一致
（--threads 不向二进制透传）。程序默认把比对结果写到 stdout，本驱动在指定 -o/--output 时重定向落盘。
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
    "search": "fasta36：蛋白/核酸相似性搜索（启发式，快）",
    "ssearch": "ssearch36：Smith-Waterman 全动态规划搜索（核酸/蛋白，慢但敏感）",
    "fastx": "fastx36：翻译后核酸序列查蛋白库",
    "fasty": "fasty36：允许移码的翻译后核酸搜索",
    "ggsearch": "ggsearch36：全全局比对搜索",
    "glsearch": "glsearch36：半全局比对搜索",
    "lalign": "lalign36：输出多条局部比对（Local alignment）",
}

# 子命令 -> 二进制（惰性解析）
BINARIES = {
    "search": "fasta36",
    "ssearch": "ssearch36",
    "fastx": "fastx36",
    "fasty": "fasty36",
    "ggsearch": "ggsearch36",
    "glsearch": "glsearch36",
    "lalign": "lalign36",
}

# 所有子命令均把结果写 stdout
STDOUT_SUBCOMMANDS = set(SUBCOMMANDS)


class FastaSkill(base.SkillBase):
    software = "fasta"
    binary = "fasta36"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析所需二进制（fasta36/ssearch36/...）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 FASTA 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(BINARIES[subcommand])
        query = kw.get("query")
        library = kw.get("library") or kw.get("db")
        if not query or not library:
            raise ValueError(f"{subcommand} 缺少必填参数 query/library")

        cmd: list[str] = [binary, str(query), str(library)]

        if kw.get("output_format") is not None:
            cmd += ["-m", str(kw["output_format"])]
        if kw.get("evalue") is not None:
            cmd += ["-E", str(kw["evalue"])]
        if kw.get("score_matrix") is not None:
            cmd += ["-s", str(kw["score_matrix"])]
        if kw.get("top_scores") is not None:
            cmd += ["-b", str(kw["top_scores"])]

        # 高级透传（慎用）
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
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（FASTA 单线程，仅接口一致）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--extra-args", help="透传给底层程序的额外参数")


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("-m", "--output-format", type=int, help="输出格式（如 8=制表，默认比对）")
    p.add_argument("-E", "--evalue", help="E-value 阈值（如 1e-5）")
    p.add_argument("-s", "--score-matrix", help="打分矩阵（如 BLOSUM62）")
    p.add_argument("-b", "--top-scores", type=int, help="每条查询显示的 top 命中数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fasta-skill",
        description="fasta native 技能驱动（fasta36/ssearch36/fastx36/... 搜索工具包）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    for name in SUBCOMMANDS:
        sp = sub.add_parser(name, help=SUBCOMMANDS[name])
        sp.add_argument("query", help="查询序列文件（FASTA）")
        sp.add_argument("library", help="目标库序列文件（FASTA）")
        sp.add_argument("-o", "--output", help="结果输出路径（默认写 stdout）")
        _add_common_opts(sp)
        _add_runtime_opts(sp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(FastaSkill().schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FastaSkill()
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

    # stdout 结果重定向到 --output
    if getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
