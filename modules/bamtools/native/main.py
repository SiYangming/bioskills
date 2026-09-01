#!/usr/bin/env python3
"""bamtools native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py convert --bam in.bam --outdir out --format fasta --prefix reads
   python main.py stats --bam in.bam
   python main.py sort --bam in.bam --out sorted.bam --threads 8
   python main.py index --bam sorted.bam
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py convert ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/bamtools_convert.py：
  bamtools convert -format <fmt> -in <bam> -out <out>
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

# bamtools convert 支持的输出格式（与 bamtools_convert.py 的 ALLOWED_FORMATS 一致）
ALLOWED_FORMATS = {"bed", "fasta", "fastq", "json", "pileup", "sam", "yaml"}

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "convert": "BAM -> 其他格式（fasta/fastq/sam/bed/json/pileup/yaml）",
    "count": "统计 BAM 中比对数量",
    "stats": "输出 BAM 基本统计",
    "header": "打印 BAM header（SAM 头）",
    "index": "为 BAM 建立索引（.bai）",
    "sort": "按 region/name/size 排序 BAM",
}


def _derive_prefix_from_bam(bam_path: str) -> str:
    name = Path(bam_path).name
    if name.endswith(".bam"):
        return name[:-4]
    return Path(bam_path).stem


class BamToolsSkill(base.SkillBase):
    software = "bamtools"
    binary = "bamtools"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 bamtools 命令行。"""
        binary = self._resolve_binary()
        cmd: list[str] = [binary, subcommand]

        if subcommand == "convert":
            fmt = kw.get("format", "fasta")
            if fmt not in ALLOWED_FORMATS:
                raise ValueError(f"不支持的格式: {fmt}，允许值: {sorted(ALLOWED_FORMATS)}")
            bam = kw.get("bam") or kw.get("input")
            if not bam:
                raise ValueError("convert 需要输入 BAM（--bam）")
            outdir = Path(kw.get("outdir") or ".")
            prefix = kw.get("prefix") or _derive_prefix_from_bam(str(bam))
            out_path = outdir / f"{prefix}.{fmt}"
            if kw.get("region"):
                cmd += ["-region", str(kw["region"])]
            cmd += ["-format", fmt, "-in", str(bam), "-out", str(out_path)]
        else:
            # count / stats / header / index / sort 通用 -in 注入
            bam = kw.get("bam") or kw.get("input")
            if bam:
                cmd += ["-in", str(bam)]
            out = kw.get("out") or kw.get("output")
            if subcommand == "sort":
                if not out:
                    raise ValueError("sort 需要输出文件（--out）")
                cmd += ["-out", str(out)]
                if kw.get("sort_by"):
                    cmd += ["-by", str(kw["sort_by"])]
            elif subcommand == "index" and out:
                cmd += ["-out", str(out)]

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
        prog="bamtools-skill",
        description="bamtools native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # convert
    pc = sub.add_parser("convert", help=SUBCOMMANDS["convert"])
    pc.add_argument("--bam", required=True, help="输入 BAM 文件")
    pc.add_argument("--outdir", default=".", help="输出目录（默认当前目录）")
    pc.add_argument("--format", choices=sorted(ALLOWED_FORMATS), default="fasta",
                    help="输出格式（默认 fasta）")
    pc.add_argument("--prefix", default=None, help="输出前缀（默认从 BAM 文件名推断）")
    pc.add_argument("--region", default=None, help="区域字符串（如 chr1:100-200）")
    pc.add_argument("--extra-args", default="", help="透传 bamtools convert 的附加参数")
    _add_runtime_opts(pc)

    # count / stats / header（单输入）
    for name in ("count", "stats", "header"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("--bam", required=True, help="输入 BAM 文件")
        _add_runtime_opts(ps)

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("--bam", required=True, help="输入 BAM 文件")
    pi.add_argument("--out", default=None, help="输出索引路径（默认 <bam>.bai）")
    _add_runtime_opts(pi)

    # sort
    psort = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    psort.add_argument("--bam", required=True, help="输入 BAM 文件")
    psort.add_argument("--out", required=True, help="输出排序 BAM")
    psort.add_argument("--by", choices=["region", "name", "size"], default=None,
                       help="排序依据（默认 bamtools 缺省）")
    _add_runtime_opts(psort)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = BamToolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BamToolsSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
        return 0

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
