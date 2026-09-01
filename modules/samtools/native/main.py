#!/usr/bin/env python3
"""samtools native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py view -bS input.sam -o out.bam --threads 8
   python main.py sort -o sorted.bam --threads 8 input.bam
   python main.py index input.bam
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（-@）与临时目录优化。
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

# 子命令 -> 是否需要 -o 输出参数 / 是否生成索引
SUPPORTS_OUTPUT = {"view", "sort", "mpileup", "stats", "depth", "merge"}
SUPPORTS_THREADS = {"view", "sort", "mpileup", "merge"}
SUPPORTS_REGION = {"view", "stats", "depth", "mpileup"}

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "view": "SAM/BAM/CRAM 互转与过滤提取",
    "sort": "按坐标 / read name 排序",
    "index": "为 BAM/CRAM 建立索引",
    "flagstat": "比对统计（flag 计数）",
    "idxstats": "按参考序列的比对统计",
    "stats": "全量比对统计报告",
    "depth": "每个位点 / 区域的测序深度",
    "mpileup": "pileup 生成（变异检测前序）",
    "faidx": "为 FASTA 建立索引",
    "merge": "合并多个 BAM",
    "quickcheck": "快速校验 BAM/CRAM 完整性",
}


class SamtoolsSkill(base.SkillBase):
    software = "samtools"
    binary = "samtools"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 samtools 命令行。"""
        binary = self._resolve_binary()
        cmd: list[str] = [binary, subcommand]

        # 通用格式 / 过滤参数（view/sort 等通用）
        output_format = kw.get("output_format")
        if output_format and subcommand in ("view", "sort"):
            cmd += ["-O", output_format]

        # 线程注入
        threads = self._effective_threads(subcommand, kw.get("threads"))
        if subcommand in SUPPORTS_THREADS:
            cmd += ["-@", str(threads)]

        # view / sort 专属过滤参数
        if subcommand == "view":
            if kw.get("filter_flags"):
                cmd += ["-F", str(kw["filter_flags"])]
            if kw.get("require_flags"):
                cmd += ["-f", str(kw["require_flags"])]
            if kw.get("min_mapq") is not None:
                cmd += ["-q", str(kw["min_mapq"])]
            # -b 直接输出 BAM（无 -O 时的便捷）
            if kw.get("output_format") == "BAM" and "-O" not in cmd:
                cmd.append("-b")

        # 输出文件
        output = kw.get("output")
        if output and subcommand in SUPPORTS_OUTPUT:
            cmd += ["-o", str(output)]

        # sort 模式
        if subcommand == "sort" and kw.get("sort_by_name"):
            cmd.append("-n")
        if subcommand == "sort":
            # 临时目录优化
            cmd += ["-T", os.path.join(self.tmpdir, f"samtools_sort.{os.getpid()}")]

        # index 选项
        if subcommand == "index" and kw.get("index_format") == "csi":
            cmd.append("-c")

        # merge: BAM 列表文件 or 多个位置参数
        if subcommand == "merge":
            bam_list = kw.get("bam_list")
            if bam_list:
                cmd += ["-b", str(bam_list)]

        # mpileup: 参考序列
        if subcommand == "mpileup" and kw.get("fasta"):
            cmd += ["-f", str(kw["fasta"])]

        # faidx: 参考序列
        if subcommand == "faidx":
            fasta = kw.get("fasta") or kw.get("input")
            if fasta:
                cmd.append(str(fasta))
            if kw.get("region"):
                cmd.append(str(kw["region"]))
            return cmd  # faidx 不走 input 位置参数

        # 主输入位置参数
        inp = kw.get("input") or kw.get("bam")
        if inp:
            cmd.append(str(inp))

        # 区域（view/stats/depth/mpileup）
        region = kw.get("region")
        if region and subcommand in SUPPORTS_REGION:
            cmd.append(str(region))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="samtools-skill",
        description="samtools native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # view
    pv = sub.add_parser("view", help=SUBCOMMANDS["view"])
    _add_common_io(pv)
    pv.add_argument("-O", "--output-format", choices=["SAM", "BAM", "CRAM", "JSON"])
    pv.add_argument("-F", "--filter-flags")
    pv.add_argument("--require-flags")
    pv.add_argument("-q", "--min-mapq", type=int)
    _add_runtime_opts(pv)

    # sort
    ps = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    _add_common_io(ps)
    ps.add_argument("-O", "--output-format", choices=["SAM", "BAM", "CRAM"])
    ps.add_argument("-n", "--sort-by-name", action="store_true")
    _add_runtime_opts(ps)

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("input", help="BAM/CRAM 文件")
    pi.add_argument("-c", "--index-format", choices=["bai", "csi"])
    _add_runtime_opts(pi)

    # flagstat / idxstats / quickcheck / stats（单输入）
    for name in ("flagstat", "idxstats", "stats", "quickcheck"):
        pf = sub.add_parser(name, help=SUBCOMMANDS[name])
        pf.add_argument("input", help="BAM 文件")
        if name == "stats":
            pf.add_argument("--region")
        _add_runtime_opts(pf)

    # depth
    pd = sub.add_parser("depth", help=SUBCOMMANDS["depth"])
    pd.add_argument("input", help="BAM 文件")
    pd.add_argument("--region")
    _add_runtime_opts(pd)

    # mpileup
    pm = sub.add_parser("mpileup", help=SUBCOMMANDS["mpileup"])
    _add_common_io(pm)
    pm.add_argument("-f", "--fasta", help="参考序列 FASTA")
    _add_runtime_opts(pm)

    # merge
    pmg = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pmg.add_argument("-o", "--output", required=True)
    pmg.add_argument("-b", "--bam-list", help="含 BAM 路径列表的文本文件")
    pmg.add_argument("input", nargs="?", help="单个 BAM（多个时用 -b）")
    _add_runtime_opts(pmg)

    # faidx
    pfaidx = sub.add_parser("faidx", help=SUBCOMMANDS["faidx"])
    pfaidx.add_argument("input", help="FASTA 文件")
    pfaidx.add_argument("--region", help="区域（如 chr1:1000-2000）")
    _add_runtime_opts(pfaidx)

    return p


def _add_common_io(p: argparse.ArgumentParser) -> None:
    p.add_argument("input", help="输入文件（SAM/BAM/CRAM）")
    p.add_argument("-o", "--output", help="输出文件")
    p.add_argument("--region", help="区域字符串")


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
        skill = SamtoolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SamtoolsSkill()
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

    # 非捕获类（无 stdout）的子命令直接继承退出码
    if not result.stdout and not result.stderr:
        return result.returncode
    out_file = getattr(ns, "output", None)
    if result.stdout and not out_file:
        # flagstat/idxstats/quickcheck 等的 stdout 直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
