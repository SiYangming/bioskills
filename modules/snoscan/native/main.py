#!/usr/bin/env python3
"""snoscan native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py search Sc-rRNA.fa query.fa -m Sc-meth.sites -o hits.txt --threads 1
   python main.py yeast  Sc-rRNA.fa query.fa -o hits.txt
   python main.py sort hits.txt -P -S 5
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（依据上行 `snoscan -h` 实测输出，snoscan 1.0 / 2020-09-04）：
  search   snoscan [-m <meth>] [-o <out>] [-s] [-l N] [-C S] [-D S] [-X S]
                    [-c S] [-d N] [-p N] [-i N] [-M N] [-V] <rRNA.fa> <query.fa>
  yeast    snoscanY ...（同 search 接口）
  human    snoscanH ...（同 search 接口）
  archaea  snoscanA ...（同 search 接口）
  sort     sort-snos [-P] [-H] [-R|-r] [-M|-U] [-T N] [-S S] [-m S] [-e E] [-F] <hits>
snoscan 为单进程程序，无并行参数；--threads 仅记录，不注入命令行。
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
    "search": "C/D box 甲基化引导 snoRNA 预测（snoscan：<rRNA.fa> <query.fa>）",
    "yeast": "酵母物种预设（snoscanY，同 search 接口）",
    "human": "人物种预设（snoscanH，同 search 接口）",
    "archaea": "古菌物种预设（snoscanA，同 search 接口）",
    "sort": "snoRNA 命中排序/过滤/去重（sort-snos <hits file>）",
}

# 需要二进制文件的子命令 -> 二进制名（物种预设走各自的包装二进制）
_BINARY_BY_SUBCOMMAND = {
    "search": "snoscan",
    "yeast": "snoscanY",
    "human": "snoscanH",
    "archaea": "snoscanA",
    "sort": "sort-snos",
}


class SnoscanSkill(base.SkillBase):
    software = "snoscan"
    binary = "snoscan"

    def _resolve_subcommand_binary(self, subcommand: str) -> str:
        """按子命令解析对应可执行文件（物种预设/排序器各为独立二进制）。"""
        self.binary = _BINARY_BY_SUBCOMMAND[subcommand]
        return self._resolve_binary()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 snoscan / sort-snos 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_subcommand_binary(subcommand)
        cmd: list[str] = [binary]

        if subcommand in ("search", "yeast", "human", "archaea"):
            # 选项（依据 snoscan -h；值型选项仅在提供时注入）
            if kw.get("methylation"):
                cmd += ["-m", str(kw["methylation"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("save_sno"):
                cmd.append("-s")
            if kw.get("min_pairing") is not None:
                cmd += ["-l", str(kw["min_pairing"])]
            if kw.get("c_box_score") is not None:
                cmd += ["-C", str(kw["c_box_score"])]
            if kw.get("d_box_score") is not None:
                cmd += ["-D", str(kw["d_box_score"])]
            if kw.get("final_score") is not None:
                cmd += ["-X", str(kw["final_score"])]
            if kw.get("comp_score") is not None:
                cmd += ["-c", str(kw["comp_score"])]
            if kw.get("max_box_dist") is not None:
                cmd += ["-d", str(kw["max_box_dist"])]
            if kw.get("min_dist") is not None:
                cmd += ["-p", str(kw["min_dist"])]
            if kw.get("init_pos") is not None:
                cmd += ["-i", str(kw["init_pos"])]
            if kw.get("max_meth_dist") is not None:
                cmd += ["-M", str(kw["max_meth_dist"])]
            if kw.get("verbose"):
                cmd.append("-V")
            # 两个位置参数：<rRNA sequence file> <query sequence file>
            rrna = kw.get("rrna")
            query = kw.get("query")
            if not rrna or not query:
                raise ValueError(
                    f"{subcommand} 缺少必填位置参数：rrna（靶 rRNA）与 query（待查序列）"
                )
            cmd += [str(rrna), str(query)]

        elif subcommand == "sort":
            # sort-snos：日志/过滤选项（依据 sort-snos 无参运行实测输出）
            if kw.get("sort_by_site"):
                cmd.append("-P")
            if kw.get("sort_by_hit"):
                cmd.append("-H")
            if kw.get("remove_dups"):
                cmd.append("-R")
            if kw.get("mapped_only"):
                cmd.append("-M")
            if kw.get("unmapped_only"):
                cmd.append("-U")
            if kw.get("top") is not None:
                cmd += ["-T", str(kw["top"])]
            if kw.get("min_score") is not None:
                cmd += ["-S", str(kw["min_score"])]
            if kw.get("max_score") is not None:
                cmd += ["-m", str(kw["max_score"])]
            if kw.get("grep_expr"):
                cmd += ["-e", str(kw["grep_expr"])]
            if kw.get("filter_only"):
                cmd.append("-F")
            hits = kw.get("hits")
            if not hits:
                raise ValueError("sort 缺少必填位置参数 hits（snoRNA 命中文件）")
            cmd.append(str(hits))

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
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="snoscan-skill",
        description="snoscan native 技能驱动（snoScAn C/D box snoRNA 预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # search / 物种预设共用同一接口
    for name, helptext in (
        ("search", SUBCOMMANDS["search"]),
        ("yeast", SUBCOMMANDS["yeast"]),
        ("human", SUBCOMMANDS["human"]),
        ("archaea", SUBCOMMANDS["archaea"]),
    ):
        ps = sub.add_parser(name, help=helptext)
        ps.add_argument("rrna", help="靶 rRNA 序列文件（第 1 位置参数）")
        ps.add_argument("query", help="待查序列文件（第 2 位置参数，FASTA）")
        ps.add_argument("-m", "--methylation", help="已知甲基化位点文件")
        ps.add_argument("-o", "--output", help="候选命中输出文件")
        ps.add_argument("-s", "--save-sno", action="store_true", help="保存候选 snoRNA 序列")
        ps.add_argument("-l", "--min-pairing", type=int, help="互补区最小长度（默认 9）")
        ps.add_argument("-C", "--c-box-score", type=float, help="C box 打分阈值")
        ps.add_argument("-D", "--d-box-score", type=float, help="D' box 打分阈值")
        ps.add_argument("-X", "--final-score", type=float, help="最终综合打分阈值")
        ps.add_argument("-c", "--comp-score", type=float, help="互补区匹配最低分")
        ps.add_argument("-d", "--max-box-dist", type=int, help="C/D box 最大间距")
        ps.add_argument("-p", "--min-dist", type=int, help="D' box 存在时的最小间距（默认 10）")
        ps.add_argument("-i", "--init-pos", type=int, help="从序列指定位置开始扫描")
        ps.add_argument("-M", "--max-meth-dist", type=int, help="到已知甲基化位点的最大距离")
        ps.add_argument("-V", "--verbose", action="store_true", help="输出详细信息")
        ps.add_argument("--extra-args", help="透传给 snoscan 的额外参数")
        _add_runtime_opts(ps)

    # sort
    pt = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    pt.add_argument("hits", help="snoRNA 命中文件（sort-snos 输入）")
    pt.add_argument("-P", "--sort-by-site", action="store_true", help="按 rRNA 互补区位置排序")
    pt.add_argument("-H", "--sort-by-hit", action="store_true", help="按命中在待查序列位置排序")
    pt.add_argument("-R", "--remove-dups", action="store_true", help="按位置排序并去低分重复")
    pt.add_argument("-M", "--mapped-only", action="store_true", help="仅输出已知甲基化位点命中")
    pt.add_argument("-U", "--unmapped-only", action="store_true", help="仅输出未定位位点命中")
    pt.add_argument("-T", "--top", type=int, help="每个甲基化位点保留前 N 条（默认 50）")
    pt.add_argument("-S", "--min-score", type=float, help="要求最低打分")
    pt.add_argument("-m", "--max-score", type=float, help="排除高于该打分的命中")
    pt.add_argument("-e", "--grep-expr", help="仅提取 header 含该表达式的 snoRNA")
    pt.add_argument("-F", "--filter-only", action="store_true", help="只过滤不排序")
    pt.add_argument("--extra-args", help="透传给 sort-snos 的额外参数")
    _add_runtime_opts(pt)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（snoscan 单进程，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = SnoscanSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SnoscanSkill()
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
