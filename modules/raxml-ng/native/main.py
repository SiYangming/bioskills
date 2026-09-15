#!/usr/bin/env python3
"""raxml-ng native 标准入口驱动（RAxML-NG 2.0.x）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py all      --msa msa.phy --model GTR+G --threads 8 --bs-trees 100
   python main.py search   --msa msa.phy --model GTR+G --threads 8
   python main.py evaluate --msa msa.phy --tree tree.nwk --model GTR+G --threads 8
   python main.py parse    --msa msa.phy
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（统一 raxml-ng --<mode> 风格）：
  all       raxml-ng --all --msa <aln> --model <m> --threads <N> [--bs-trees <n>] [--prefix <p>]
  ml        raxml-ng --ml --msa <aln> --model <m> --threads <N>
  search    raxml-ng --search --msa <aln> --model <m> --threads <N>
  evaluate  raxml-ng --evaluate --msa <aln> --tree <tree> --model <m> --threads <N>
  parse     raxml-ng --parse --msa <aln>
  version   raxml-ng --version
RAxML-NG 为 CPU 密集工具：驱动按线程优先级注入 --threads
（--threads > per_subcommand_threads > default_cpus）。
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
    "all": "ML 树搜索 + bootstrap + 模型选择（--all；--msa/--model/--threads）",
    "ml": "ML 树搜索（--ml）",
    "search": "拓扑搜索（--search）",
    "evaluate": "在给定拓扑上评估（--evaluate --tree）",
    "parse": "解析/压缩比对（--parse --msa/--model；产物 <prefix>.raxml.rba，位点被压缩时另出 .reduced.phy）",
    "version": "打印 RAxML-NG 版本（--version）",
}

# 子命令 -> raxml-ng 主模式开关
MODE_FLAGS = {"all": "--all", "ml": "--ml", "search": "--search", "evaluate": "--evaluate"}


class RaxmlNgSkill(base.SkillBase):
    software = "raxml-ng"
    binary = "raxml-ng"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 raxml-ng 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()

        if subcommand == "version":
            return [binary, "--version"]

        msa = kw.get("msa") or kw.get("input")
        if not msa:
            raise ValueError(f"{subcommand} 缺少必填参数 msa（输入比对，--msa）")

        cmd: list[str] = [binary]

        if subcommand == "parse":
            cmd += ["--parse", "--msa", str(msa), "--model", str(kw.get("model") or "GTR+G")]
        elif subcommand == "evaluate":
            tree = kw.get("tree")
            if not tree:
                raise ValueError("evaluate 缺少必填参数 tree（--tree）")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--evaluate", "--msa", str(msa), "--tree", str(tree),
                    "--model", str(kw.get("model") or "GTR+G"), "--threads", str(threads)]
        else:  # all / ml / search
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += [MODE_FLAGS[subcommand], "--msa", str(msa),
                    "--model", str(kw.get("model") or "GTR+G"), "--threads", str(threads)]
            if subcommand == "all" and kw.get("bootstrap_reps") is not None:
                cmd += ["--bs-trees", str(kw["bootstrap_reps"])]

        if kw.get("prefix"):
            cmd += ["--prefix", str(kw["prefix"])]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="raxml-ng-skill",
        description="raxml-ng native 技能驱动（RAxML-NG 2.0.x，统一 --<mode> 风格，自动注入 --threads）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _add_common(sp: argparse.ArgumentParser, model: bool = True) -> None:
        sp.add_argument("--msa", help="输入多序列比对（FASTA/Phylip）")
        if model:
            sp.add_argument("--model", default="GTR+G",
                            help="进化模型（GTR+G / GTR+G4 / LG+G；all 可用 MFP+MERGE，默认 GTR+G）")
        sp.add_argument("--prefix", help="输出文件前缀（缺省 <msa>.raxml）")
        sp.add_argument("--extra-args", help="透传给 raxml-ng 的额外参数")

    # all
    pa = sub.add_parser("all", help=SUBCOMMANDS["all"])
    _add_common(pa)
    pa.add_argument("--bs-trees", dest="bootstrap_reps", type=int, help="bootstrap 重复次数（--bs-trees）")
    _add_runtime_opts(pa)

    # ml
    pm = sub.add_parser("ml", help=SUBCOMMANDS["ml"])
    _add_common(pm)
    _add_runtime_opts(pm)

    # search
    ps = sub.add_parser("search", help=SUBCOMMANDS["search"])
    _add_common(ps)
    _add_runtime_opts(ps)

    # evaluate
    pe = sub.add_parser("evaluate", help=SUBCOMMANDS["evaluate"])
    _add_common(pe)
    pe.add_argument("--tree", help="输入树（Newick，--tree）")
    _add_runtime_opts(pe)

    # parse（RAxML-NG 的 --parse 同样要求 --model，见官方用法）
    pp = sub.add_parser("parse", help=SUBCOMMANDS["parse"])
    _add_common(pp)
    _add_runtime_opts(pp)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 --threads；默认 8）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = RaxmlNgSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RaxmlNgSkill()
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
