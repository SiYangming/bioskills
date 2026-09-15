#!/usr/bin/env python3
"""htseq native 标准入口驱动（HTSeq / htseq-count）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py count -f bam -r pos -s no -a 10 -t exon -i gene_id accepted_hits.bam genome.gtf --output counts.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐官方 htseq-count）：
  htseq-count -f <sam|bam> -r <name|pos> -s <yes|no|reverse> [-a N] -t <feature> -i <attr>
              [-m <mode>] [-o <samout>] <alignment_file> <gff_file>
count 结果默认写 stdout；驱动可用 --output 将其落盘（教学文档示例的 `> counts.txt` 等价）。
注意：htseq-count 为单线程工具（无线程参数）；--threads 仅为对齐 SkillBase 接口而接受，不参与命令拼装。
"""

from __future__ import annotations

import argparse
import json
import shlex
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
    "count": "htseq-count 从 SAM/BAM 与 GTF/GFF 计算基因表达量（-f/-r/-s/-a/-t/-i/-m）",
}


class HtseqSkill(base.SkillBase):
    software = "htseq"
    binary = "htseq-count"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 htseq-count 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

        samfile = kw.get("samfile") or kw.get("input")
        gfffile = kw.get("gfffile") or kw.get("gtf")
        if not samfile:
            raise ValueError("count 缺少必填参数 samfile（输入 SAM/BAM）")
        if not gfffile:
            raise ValueError("count 缺少必填参数 gfffile（参考注释 GTF/GFF）")

        binary = self._resolve_binary()
        cmd: list[str] = [
            binary,
            "-f", str(kw.get("format") or "sam"),
            "-r", str(kw.get("order") or "name"),
            "-s", str(kw.get("stranded") or "no"),
        ]
        if kw.get("minaqual") is not None:
            cmd += ["-a", str(kw["minaqual"])]
        cmd += ["-t", str(kw.get("featuretype") or "exon")]
        cmd += ["-i", str(kw.get("idattr") or "gene_id")]
        if kw.get("mode"):
            cmd += ["-m", str(kw["mode"])]
        if kw.get("samout"):
            cmd += ["-o", str(kw["samout"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        # htseq-count 位置参数顺序：alignment_file gff_file
        cmd += [str(samfile), str(gfffile)]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。

    注意：htseq-count 为单线程工具，--threads 仅为接口对齐而接受，不参与命令拼装。
    """
    p.add_argument("--threads", type=int, help="覆盖默认线程数（htseq-count 单线程，实际不生效）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="htseq-skill",
        description="htseq native 技能驱动（htseq-count 定量）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("count", help=SUBCOMMANDS["count"])
    pc.add_argument("samfile", help="输入比对文件 SAM/BAM（位置参数）")
    pc.add_argument("gfffile", help="参考注释 GTF/GFF（位置参数）")
    pc.add_argument("-f", "--format", default="sam", help="输入格式：sam|bam（-f，默认 sam）")
    pc.add_argument("-r", "--order", default="name", help="排序方式：name|pos（-r，默认 name）")
    pc.add_argument("-s", "--stranded", default="no", help="链特异性：yes|no|reverse（-s）")
    pc.add_argument("-a", "--minaqual", type=int, default=10, help="最小比对质量（-a，默认 10）")
    pc.add_argument("-t", "--featuretype", default="exon", help="计数特征类型（-t，默认 exon）")
    pc.add_argument("-i", "--idattr", default="gene_id", help="分组属性（-i，默认 gene_id）")
    pc.add_argument("-m", "--mode", default="union",
                    help="计数模式：union|intersection-strict|intersection-nonempty（-m）")
    pc.add_argument("-o", "--samout", help="输出带注释的 SAM（-o，可选）")
    pc.add_argument("--output", help="将计数结果（stdout）写入该文件（驱动层重定向）")
    pc.add_argument("--extra-args", help="透传给 htseq-count 的额外参数（慎用）")
    _add_runtime_opts(pc)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = HtseqSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = HtseqSkill()
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

    # count 结果默认写 stdout；提供 --output 时落盘（等价 `> counts.txt`）
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
