#!/usr/bin/env python3
"""kent native 标准入口驱动（UCSC kent / jksrc 多工具源码树）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py faToTwoBit genome.fa genome.2bit
   python main.py twoBitToFa genome.2bit genome.fa
   python main.py twoBitInfo genome.2bit genome.tab
   python main.py blat genome.2bit query.fa out.psl --threads 8
   python main.py bedToBigBed regions.bed chrom.sizes regions.bigBed --type bed6
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  faToTwoBit  faToTwoBit <in.fa> <out.2bit>
  twoBitToFa  twoBitToFa <in.2bit> <out.fa>
  twoBitInfo  twoBitInfo <in.2bit> <out.tab>
  blat        blat <db> <query> <out.psl> -threads=N
  bedToBigBed bedToBigBed <in.bed> <chrom.sizes> <out.bigBed> [-type=<type>]
kent 为多工具源码树，本驱动按子命令惰性解析对应二进制；线程仅对 blat 注入。
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
    "faToTwoBit": "FASTA -> 2bit（faToTwoBit <in.fa> <out.2bit>）",
    "twoBitToFa": "2bit -> FASTA（twoBitToFa <in.2bit> <out.fa>）",
    "twoBitInfo": "2bit -> 序列信息表（twoBitInfo <in.2bit> <out.tab>）",
    "blat": "快速比对（blat <db> <query> <out.psl> -threads=N）",
    "bedToBigBed": "BED -> bigBed（bedToBigBed <in.bed> <chrom.sizes> <out.bigBed>）",
}

# 子命令 -> 可执行文件名（与子命令同名）
SUBCOMMAND_BINARY = {k: k for k in SUBCOMMANDS}


class KentSkill(base.SkillBase):
    software = "kent"
    binary = "faToTwoBit"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_tool(self, name: str) -> str:
        """惰性解析指定 kent 工具路径（测试可 monkeypatch）。"""
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先安装 kent（Docker/Apptainer 自建镜像或官方预编译二进制）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 kent 工具命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_tool(SUBCOMMAND_BINARY[subcommand])
        cmd: list[str] = [binary]

        if subcommand == "faToTwoBit":
            src = kw.get("input")
            out = kw.get("output")
            if not src or not out:
                raise ValueError("faToTwoBit 需要 <input.fa> <output.2bit>")
            cmd += [str(src), str(out)]

        elif subcommand == "twoBitToFa":
            src = kw.get("input")
            out = kw.get("output")
            if not src or not out:
                raise ValueError("twoBitToFa 需要 <input.2bit> <output.fa>")
            cmd += [str(src), str(out)]

        elif subcommand == "twoBitInfo":
            src = kw.get("input")
            out = kw.get("output")
            if not src or not out:
                raise ValueError("twoBitInfo 需要 <input.2bit> <output.tab>")
            cmd += [str(src), str(out)]

        elif subcommand == "blat":
            db = kw.get("db")
            query = kw.get("query")
            out = kw.get("output")
            if not db or not query or not out:
                raise ValueError("blat 需要 <db> <query> <output.psl>")
            cmd += [str(db), str(query), str(out)]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd.append(f"-threads={threads}")

        elif subcommand == "bedToBigBed":
            src = kw.get("input")
            chrom = kw.get("chrom_sizes")
            out = kw.get("output")
            if not src or not chrom or not out:
                raise ValueError("bedToBigBed 需要 <input.bed> <chrom.sizes> <output.bigBed>")
            cmd += [str(src), str(chrom), str(out)]
            if kw.get("type"):
                cmd.append(f"-type={kw['type']}")

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
        prog="kent-skill",
        description="kent native 技能驱动（UCSC kent / jksrc 代表性工具）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # faToTwoBit
    p1 = sub.add_parser("faToTwoBit", help=SUBCOMMANDS["faToTwoBit"])
    p1.add_argument("input", help="输入 FASTA")
    p1.add_argument("output", help="输出 2bit")
    p1.add_argument("--extra-args", help="透传给 faToTwoBit 的额外参数")
    _add_runtime_opts(p1)

    # twoBitToFa
    p2 = sub.add_parser("twoBitToFa", help=SUBCOMMANDS["twoBitToFa"])
    p2.add_argument("input", help="输入 2bit")
    p2.add_argument("output", help="输出 FASTA")
    p2.add_argument("--extra-args", help="透传给 twoBitToFa 的额外参数")
    _add_runtime_opts(p2)

    # twoBitInfo
    p3 = sub.add_parser("twoBitInfo", help=SUBCOMMANDS["twoBitInfo"])
    p3.add_argument("input", help="输入 2bit")
    p3.add_argument("output", help="输出信息表")
    p3.add_argument("--extra-args", help="透传给 twoBitInfo 的额外参数")
    _add_runtime_opts(p3)

    # blat
    p4 = sub.add_parser("blat", help=SUBCOMMANDS["blat"])
    p4.add_argument("db", help="数据库（2bit 或 fa 前缀）")
    p4.add_argument("query", help="查询序列 FASTA")
    p4.add_argument("output", help="输出 PSL")
    p4.add_argument("--extra-args", help="透传给 blat 的额外参数")
    _add_runtime_opts(p4)

    # bedToBigBed
    p5 = sub.add_parser("bedToBigBed", help=SUBCOMMANDS["bedToBigBed"])
    p5.add_argument("input", help="输入 BED")
    p5.add_argument("chrom_sizes", help="chrom.sizes")
    p5.add_argument("output", help="输出 bigBed")
    p5.add_argument("-type", "--type", dest="type", help="BED 类型（如 bed6）")
    p5.add_argument("--extra-args", help="透传给 bedToBigBed 的额外参数")
    _add_runtime_opts(p5)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅 blat 注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = KentSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = KentSkill()
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
