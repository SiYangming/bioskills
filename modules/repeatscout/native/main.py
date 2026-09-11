#!/usr/bin/env python3
"""repeatscout native 标准入口驱动。

RepeatScout（上游 Dfam-consortium/RepeatScout）是基于 de Bruijn 式 l-mer 种子图的
从头（de novo）重复序列家族发现工具，也是 RepeatModeler 的 RECON/RepeatScout 挖掘管线
核心组件（多数场景由 modules/repeatmodeler 的 RepeatModeler 内部调用，无需单独运行）。

本驱动内含两个官方可执行（同属 bioconda repeatscout 包，均为单线程 C 程序）：
- build_lmer_table 子命令 -> build_lmer_table：统计全基因组 l-mer 频率表
- predict 子命令        -> RepeatScout：以频率表为输入做种子延伸，输出重复家族共有序列 FASTA

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py build_lmer_table genome.fasta -freq genome.freq
   python main.py predict -sequence genome.fasta -freq genome.freq -output repeats.fa
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令接受 --threads / --tmpdir（--tmpdir 同时注入 TMPDIR 环境变量）。
注意：build_lmer_table 与 RepeatScout 均无并行参数，--threads 仅作为运行期选项被接受、不注入命令行。

参数要点（官方 usage，2026-09 核实 v1.0.7 源码）：
- build_lmer_table -l <l> -sequence <seq> -freq <output> [opts]
- RepeatScout [opts] [-ranges <file>] -sequence <file> -output <file> -freq <file> -l #
- 官方 -l 是「l-mer 长度」（默认 ceil(log4(L)+1)），build_lmer_table 与 RepeatScout
  必须取同一值；「可报告的最短重复长度」官方对应 -goodlength（默认 50）。
"""
from __future__ import annotations

import argparse
import json
import shutil
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
    "build_lmer_table": "build_lmer_table：统计序列的 l-mer 频率表（-sequence/-freq），供 RepeatScout 使用",
    "predict": "RepeatScout：以频率表为输入发现重复家族，输出共有序列 FASTA（-sequence/-freq/-output）",
}


class RepeatScoutSkill(base.SkillBase):
    software = "repeatscout"
    binary = "RepeatScout"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/repeatscout/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（build_lmer_table / RepeatScout），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda repeatscout / 官方容器会同时提供 build_lmer_table 与 RepeatScout）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 build_lmer_table / RepeatScout 命令行。"""
        if subcommand == "build_lmer_table":
            binary = self._resolve_tool("build_lmer_table")
            # 位置参数与 -sequence 二选一（位置参数名 sequence_pos，选项名 sequence）
            sequence = kw.get("sequence") or kw.get("sequence_pos")
            if not sequence:
                raise RuntimeError("build_lmer_table 需要 sequence（-sequence/--sequence 或位置参数）")
            freq = kw.get("freq")
            if not freq:
                raise RuntimeError("build_lmer_table 需要 -freq/--freq（l-mer 频率表输出文件）")

            cmd: list[str] = [binary]
            lmer = kw.get("lmer_length")
            if lmer is not None:
                cmd += ["-l", str(lmer)]
            # 官方 usage：build_lmer_table -l <l> -sequence <seq> -freq <output> [opts]
            cmd += ["-sequence", str(sequence), "-freq", str(freq)]
        elif subcommand == "predict":
            binary = self._resolve_tool("RepeatScout")
            sequence = kw.get("sequence")
            if not sequence:
                raise RuntimeError("predict 需要 -sequence/--sequence（输入序列 FASTA）")
            freq = kw.get("freq")
            if not freq:
                raise RuntimeError("predict 需要 -freq/--freq（build_lmer_table 产出的频率表）")
            output = kw.get("output")
            if not output:
                raise RuntimeError("predict 需要 -output/-o（重复家族共有序列 FASTA 输出文件）")

            cmd = [binary]
            lmer = kw.get("lmer_length")
            if lmer is not None:
                # 官方 -l 为 l-mer 长度，须与 build_lmer_table 取值一致
                cmd += ["-l", str(lmer)]
            # 官方 usage：RepeatScout [opts] -sequence <file> -output <file> -freq <file>
            cmd += ["-sequence", str(sequence), "-freq", str(freq), "-output", str(output)]
            goodlength = kw.get("min_repeat_length")
            if goodlength is not None:
                # 官方 -goodlength：可报告的最短重复长度（默认 50）
                cmd += ["-goodlength", str(goodlength)]
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（如 -ranges/-tandemdist/-stopafter，慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="repeatscout-skill",
        description="repeatscout native 技能驱动（自动 TMPDIR；l-mer 频率表 + 从头重复家族发现）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # build_lmer_table: build_lmer_table -l <l> -sequence <seq> -freq <output>
    pb = sub.add_parser("build_lmer_table", help=SUBCOMMANDS["build_lmer_table"])
    pb.add_argument("sequence_pos", nargs="?", help="输入序列 FASTA（位置参数，等价 -sequence/--sequence）")
    pb.add_argument("-sequence", "--sequence", dest="sequence",
                    help="输入序列 FASTA（等价位置参数）")
    pb.add_argument("-freq", "--freq", required=True,
                    help="l-mer 频率表「输出」文件（供 predict -freq 复用）")
    pb.add_argument("-l", "-L", "--lmer-length", type=int, dest="lmer_length",
                    help="l-mer 长度（官方参数 -l，默认 ceil(log4(L)+1)；须与 predict 一致；-L 为本驱动兼容别名）")
    pb.add_argument("--extra-args", dest="extra_args",
                    help="透传给 build_lmer_table 的额外参数（如 -tandem/-min/-v，高级用法，慎用）")
    _add_runtime_opts(pb)

    # predict: RepeatScout -sequence <file> -output <file> -freq <file> [-l #]
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("-sequence", "--sequence", required=True, help="输入序列 FASTA")
    pp.add_argument("-freq", "--freq", required=True,
                    help="l-mer 频率表（build_lmer_table 的产物）")
    pp.add_argument("-output", "-o", "--output", required=True,
                    help="重复家族共有序列 FASTA 输出文件")
    pp.add_argument("-l", "--lmer-length", type=int, dest="lmer_length",
                    help="l-mer 长度（官方参数 -l，须与 build_lmer_table 一致）。"
                         "注意：官方 -l 是 l-mer 长度，不是最小重复长度（后者用 --min-repeat-length）")
    pp.add_argument("-goodlength", "--min-repeat-length", type=int, dest="min_repeat_length",
                    help="可报告的最短重复长度（官方 RepeatScout -goodlength，默认 50）")
    pp.add_argument("--extra-args", dest="extra_args",
                    help="透传给 RepeatScout 的额外参数（如 -ranges/-stopafter/-tandemdist，高级用法，慎用）")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int,
                   help="覆盖默认线程数（build_lmer_table/RepeatScout 均为单线程，仅满足统一契约、不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = RepeatScoutSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RepeatScoutSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # 两个子命令的正式产物均写文件（-freq / -output），进度日志走 stderr
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
