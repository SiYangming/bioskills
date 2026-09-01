#!/usr/bin/env python3
"""stringtie native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble sample.sorted.bam -G gencode.v49.annotation.gtf -o sample.stringtie.gtf --threads 8
   python main.py fix_gtf sample.stringtie.gtf -o sample.stringtie.fixed.gtf
   python main.py merge gtf_list.txt -G gencode.v49.annotation.gtf -o merged_nonredundant.gtf
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/nanoseq.smk/nanoseq.sh/run_stringtie.sh：
  assemble  stringtie <bam> --conservative -L -R -G <gtf> -o <out> -l <label> -m <min_len> -p N
  fix_gtf   awk '$4>$5{t=$4;$4=$5;$5=t}'（修复 GTF 坐标颠倒，纯文本处理，无需 stringtie）
  merge     stringtie --merge -G <gtf> -o <merged.gtf> -l MSTRG -m <min_len> <gtf_list>
所有子命令自动注入线程（-p）与临时目录优化。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 skills/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "assemble": "BAM + GTF -> 样本级转录本 GTF（stringtie 组装，长读模式）",
    "merge": "GTF 列表 -> 非冗余合并 GTF（stringtie --merge）",
    "fix_gtf": "修复 GTF 坐标颠倒（$4>$5 交换，awk 实现，无需 stringtie）",
}

# 子命令 -> 是否需要 stringtie 二进制
NEEDS_BINARY = {"assemble", "merge"}


class StringtieSkill(base.SkillBase):
    software = "stringtie"
    binary = "stringtie"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 stringtie 命令行（或 fix_gtf 的 awk 命令）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        # fix_gtf：纯文本坐标修复，不需要 stringtie 二进制
        if subcommand == "fix_gtf":
            gtf_in = kw.get("input") or kw.get("gtf")
            if not gtf_in:
                raise ValueError("fix_gtf 缺少必填参数 input（GTF 文件）")
            # awk -F'\t' -v OFS='\t' '/^#/{print;next} $4>$5{t=$4;$4=$5;$5=t} {print}'
            # 输出写 stdout，由 main() 捕获后写入 output 文件
            return [
                "awk", "-F", "\\t", "-v", "OFS=\\t",
                "/^#/{print;next} $4>$5{t=$4;$4=$5;$5=t} {print}",
                str(gtf_in),
            ]

        binary = self._resolve_binary()
        cmd: list[str] = [binary]
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "assemble":
            bam = kw.get("bam") or kw.get("input")
            if not bam:
                raise ValueError("assemble 缺少必填参数 bam（输入 BAM）")
            cmd.append(str(bam))
            # nanoseq 长读模式默认参数（值内联自 run_stringtie.sh / config.yaml）
            if kw.get("conservative", True):
                cmd.append("--conservative")
            if kw.get("long_reads", True):
                cmd.append("-L")
            if kw.get("rf_stranded", True):
                cmd.append("-R")
            gtf = kw.get("gtf")
            if gtf:
                cmd += ["-G", str(gtf)]
            out = kw.get("output")
            if out:
                cmd += ["-o", str(out)]
            label = kw.get("label") or Path(bam).stem.replace(".sorted", "").replace(".bam", "")
            cmd += ["-l", label]
            if kw.get("min_transcript_len") is not None:
                cmd += ["-m", str(kw["min_transcript_len"])]
            cmd += ["-p", str(threads)]

        elif subcommand == "merge":
            cmd.append("--merge")
            gtf = kw.get("gtf")
            if gtf:
                cmd += ["-G", str(gtf)]
            out = kw.get("output")
            if out:
                cmd += ["-o", str(out)]
            label = kw.get("label") or "MSTRG"
            cmd += ["-l", label]
            if kw.get("min_transcript_len") is not None:
                cmd += ["-m", str(kw["min_transcript_len"])]
            gtf_list = kw.get("gtf_list") or kw.get("input")
            if not gtf_list:
                raise ValueError("merge 缺少必填参数 gtf_list（GTF 列表文件）")
            cmd.append(str(gtf_list))

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
        prog="stringtie-skill",
        description="stringtie native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # assemble
    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("input", nargs="?", help="输入 BAM（别名 --bam）")
    pa.add_argument("--bam", help="输入 BAM 的别名")
    pa.add_argument("-G", "--gtf", help="参考注释 GTF")
    pa.add_argument("-o", "--output", help="输出 GTF 路径")
    pa.add_argument("-l", "--label", help="转录本前缀标签（默认取样本名）")
    pa.add_argument("-m", "--min-transcript-len", type=int, help="最小转录本长度（默认 200）")
    pa.add_argument("--no-conservative", dest="conservative", action="store_false", help="关闭 --conservative")
    pa.add_argument("--no-L", dest="long_reads", action="store_false", help="关闭 -L 长读模式")
    pa.add_argument("--no-R", dest="rf_stranded", action="store_false", help="关闭 -R RF 链特异性")
    pa.add_argument("--extra-args", help="透传给 stringtie 的额外参数")
    _add_runtime_opts(pa)

    # merge
    pm = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pm.add_argument("input", nargs="?", help="GTF 列表文件（每行一个 GTF 路径）")
    pm.add_argument("--gtf-list", help="GTF 列表文件的别名")
    pm.add_argument("-G", "--gtf", help="参考注释 GTF")
    pm.add_argument("-o", "--output", help="输出合并 GTF 路径")
    pm.add_argument("-l", "--label", help="转录本前缀标签（默认 MSTRG）")
    pm.add_argument("-m", "--min-transcript-len", type=int, help="最小转录本长度（默认 200）")
    pm.add_argument("--extra-args", help="透传给 stringtie 的额外参数")
    _add_runtime_opts(pm)

    # fix_gtf
    pf = sub.add_parser("fix_gtf", help=SUBCOMMANDS["fix_gtf"])
    pf.add_argument("input", help="输入 GTF 文件")
    pf.add_argument("-o", "--output", help="输出修复后 GTF 路径（默认 <input>.fixed.gtf）")
    _add_runtime_opts(pf)

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
        skill = StringtieSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = StringtieSkill()
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

    # fix_gtf 的 stdout 落到 output 文件（awk 写 stdout）
    if ns.subcommand == "fix_gtf" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
