#!/usr/bin/env python3
"""snogps native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py search genome.fa desc/MamGUs2.v3.desc -T targs/human.targ -t 135 -S 5 -F hits.fa
   python main.py sort results/hits.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（依据上游 src/pseudoU_test.c 的 usage 块，snoGPS 0.2 beta）：
  search  snoGPS [-D N] [-S S] [-T <target>] [-F <fasta_out>] [-t N] [-L <table>]
                  [-W] [-C] [-q] <sequence-file> <descriptor file>
  sort    sortHits.pl <hits file> [extra args]
snoGPS 为单进程程序，无并行参数；--threads 仅记录，不注入命令行。
说明：snoGPS 核心二进制由 `cd src && make` 构建，产物为 pseudoU_test，并软链为 snoGPS。
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
    "search": "H/ACA 假尿苷化引导 snoRNA 预测（snoGPS：<sequence.fa> <descriptor>）",
    "sort": "snoGPS 命中结果整理（sortHits.pl <hits file>）",
}

# 子命令 -> 二进制名
_BINARY_BY_SUBCOMMAND = {
    "search": "snoGPS",
    "sort": "sortHits.pl",
}


class SnogpsSkill(base.SkillBase):
    software = "snogps"
    binary = "snoGPS"

    def _resolve_subcommand_binary(self, subcommand: str) -> str:
        self.binary = _BINARY_BY_SUBCOMMAND[subcommand]
        return self._resolve_binary()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 snoGPS / sortHits.pl 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_subcommand_binary(subcommand)
        cmd: list[str] = [binary]

        if subcommand == "search":
            if kw.get("debug") is not None:
                cmd += ["-D", str(kw["debug"])]
            if kw.get("score_cutoff") is not None:
                cmd += ["-S", str(kw["score_cutoff"])]
            if kw.get("target"):
                cmd += ["-T", str(kw["target"])]
            if kw.get("fasta_out"):
                cmd += ["-F", str(kw["fasta_out"])]
            if kw.get("target_count") is not None:
                cmd += ["-t", str(kw["target_count"])]
            if kw.get("scoretable"):
                cmd += ["-L", str(kw["scoretable"])]
            if kw.get("watson_only"):
                cmd.append("-W")
            if kw.get("crick_only"):
                cmd.append("-C")
            if kw.get("quiet"):
                cmd.append("-q")
            sequence = kw.get("sequence")
            descriptor = kw.get("descriptor")
            if not sequence or not descriptor:
                raise ValueError(
                    "search 缺少必填位置参数：sequence（待查序列）与 descriptor（descriptor 文件）"
                )
            cmd += [str(sequence), str(descriptor)]

        elif subcommand == "sort":
            hits = kw.get("hits")
            if not hits:
                raise ValueError("sort 缺少必填位置参数 hits（snoGPS 命中文件）")
            cmd.append(str(hits))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="snogps-skill",
        description="snogps native 技能驱动（snoGPS H/ACA snoRNA 预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # search
    ps = sub.add_parser("search", help=SUBCOMMANDS["search"])
    ps.add_argument("sequence", help="待查序列文件（FASTA，可为基因组）")
    ps.add_argument("descriptor", help="descriptor 文件（定义搜索测试与参数）")
    ps.add_argument("-T", "--target", help="target 文件（目标假尿苷位点局部序列）")
    ps.add_argument("-t", "--target-count", type=int, help="从 target 文件读取的靶位点数量")
    ps.add_argument("-S", "--score-cutoff", type=float, help="总分阈值")
    ps.add_argument("-F", "--fasta-out", help="命中序列 FASTA 输出文件")
    ps.add_argument("-L", "--scoretable", help="自定义打分表文件")
    ps.add_argument("-W", "--watson-only", action="store_true", help="仅搜索 Watson 链")
    ps.add_argument("-C", "--crick-only", action="store_true", help="仅搜索 Crick 链")
    ps.add_argument("-q", "--quiet", action="store_true", help="安静模式（不输出表头）")
    ps.add_argument("-D", "--debug", type=int, help="调试级别（0/1/2）")
    ps.add_argument("--extra-args", help="透传给 snoGPS 的额外参数")
    _add_runtime_opts(ps)

    # sort
    pt = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    pt.add_argument("hits", help="snoGPS 原始命中文件（sortHits.pl 输入）")
    pt.add_argument("--extra-args", help="透传给 sortHits.pl 的额外参数")
    _add_runtime_opts(pt)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（snoGPS 单进程，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = SnogpsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SnogpsSkill()
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
