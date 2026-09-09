#!/usr/bin/env python3
"""lordec native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py correct -2 illumina.1.fastq,illumina.2.fastq -i subreads.fasta -k 17 -s 3 -o corrected.fasta --threads 8
   python main.py correct -2 illumina.fasta -i pacbio.fasta -k 19 -s 3 -o corrected.fasta
   python main.py trim -i corrected.fasta -o trimmed.fasta
   python main.py trim-split -i corrected.fasta -o trimmed_split.fasta
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py correct ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑（LoRDEC v0.9 官方 CLI；来源：官网 http://www.atgc-montpellier.fr/lordec/ usage 段）：
  lordec-correct [-2 <short reads>] [-i <PacBio reads>] [-k <k-mer>] [-s <solidity>]
                 [-o <output>] [-T <threads>] [--trials N] [--branch B] [--errorrate E]
  lordec-trim        -i <corrected reads> -o <trimmed reads>
  lordec-trim-split  -i <corrected reads> -o <trimmed reads>
说明：
  -2 可给「单文件」或「双端两文件逗号分隔」（短读可 gzip FASTA/FASTQ）；-i 长读 FASTA；
    -k k-mer 长度（细菌 k=17/19、大基因组 k=21）；-s solid k-mer 丰度阈值（典型 2–3）；
    -o 输出 corrected FASTA：大写=已纠正确碱基、小写=未能纠正。
  -T/--threads 仅在 correct 的官方 CLI 有效（trim / trim-split 为单线程程序，--threads 占位不注入）。
  更多可选参数（--trials/--branch/--errorrate/…）经 --extra-args 透传（高级用法，慎用）。
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
    "correct": "lordec-correct 主纠错：以 Illumina/短读（-2，可双端逗号两文件）建 DBG，纠正"
               "PacBio/长读（-i）的错误区，-k k-mer、-s solid 阈值，输出 corrected FASTA（大写=已纠/小写=未纠）",
    "trim": "lordec-trim 修剪：切除 corrected reads 头尾未能纠正（小写）的区段，输出修剪后 FASTA",
    "trim-split": "lordec-trim-split 修剪并拆分：切除头尾未纠区且内部未纠区长到拆分段，输出多条 FASTA",
}

# 子命令 -> 实际二进制
_BIN = {
    "correct": "lordec-correct",
    "trim": "lordec-trim",
    "trim-split": "lordec-trim-split",
}


class LordecSkill(base.SkillBase):
    software = "lordec"
    binary = "lordec-correct"  # 主二进制；build_command 内按子命令切换到 lordec-trim / lordec-trim-split

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 lordec 命令行（对齐官方 v0.9 CLI）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        # 按子命令选择二进制（self._resolve_binary 在 dry-run 时被 main 覆写为返回 self.binary）
        self.binary = _BIN[subcommand]
        binary = self._resolve_binary()

        if subcommand == "correct":
            return self._build_correct(binary, **kw)
        return self._build_trim(binary, subcommand, **kw)

    # -- 内部实现 ----------------------------------------------------------- #
    def _build_correct(self, binary: str, **kw) -> list[str]:
        """lordec-correct -2 <short> -i <long> -k <k> -s <s> -o <out> [-T threads] [extra]"""
        short_reads = kw.get("short_reads")
        input_ = kw.get("input")
        kmer_size = kw.get("kmer_size")
        solidity = kw.get("solidity")
        output = kw.get("output")
        missing = [
            name for name, val in
            (("-2", short_reads), ("-i", input_), ("-k", kmer_size),
             ("-s", solidity), ("-o", output))
            if val is None or str(val) == ""
        ]
        if missing:
            raise ValueError(f"correct 需要参数: {', '.join(missing)}（-2 短读 -i 长读 -k k-mer -s solid -o 输出）")

        cmd: list[str] = [binary, "-2", str(short_reads), "-i", str(input_),
                          "-k", str(int(kmer_size)), "-s", str(int(solidity)),
                          "-o", str(output)]
        # 线程注入：仅 correct（官方 -T；trim/trim-split 单线程无此参数）
        threads = self._effective_threads("correct", kw.get("threads"))
        cmd += ["-T", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))
        return cmd

    def _build_trim(self, binary: str, subcommand: str, **kw) -> list[str]:
        """lordec-trim / lordec-trim-split -i <corrected> -o <trimmed>"""
        input_ = kw.get("input")
        output = kw.get("output")
        missing = [name for name, val in (("-i", input_), ("-o", output))
                   if val is None or str(val) == ""]
        if missing:
            raise ValueError(f"{subcommand} 需要参数: {', '.join(missing)}（-i 输入 corrected reads -o 输出）")

        cmd: list[str] = [binary, "-i", str(input_), "-o", str(output)]

        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser, note: str) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help=note)
    p.add_argument("--tmpdir", help="覆盖默认临时目录（进程 TMPDIR）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="lordec-skill",
        description="lordec native 技能驱动（correct/trim/trim-split：Illumina 短读纠错 PacBio/长读；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("correct", help=SUBCOMMANDS["correct"])
    pc.add_argument("-2", "--short-reads", dest="short_reads",
                    help="参考短读集：单 FASTA/FASTQ（可 gzip），或双端逗号两文件，如 illumina.1.fastq,illumina.2.fastq")
    pc.add_argument("-i", "--input", help="待纠错长读（PacBio subreads FASTA/FASTQ）")
    pc.add_argument("-k", "--kmer-size", dest="kmer_size", type=int,
                    help="k-mer 长度（细菌/小基因组 k=17 或 19，大基因组 k=21）")
    pc.add_argument("-s", "--solidity", type=int,
                    help="solid k-mer 丰度阈值（典型 2–3）")
    pc.add_argument("-o", "--output", help="输出 corrected FASTA（大写=已纠/小写=未纠）")
    pc.add_argument("--extra-args", help="透传给 lordec-correct 的附加参数（如 --branch/--errorrate/--trials）")
    _add_runtime_opts(pc, "线程数（注入 lordec-correct -T）")

    for name in ("trim", "trim-split"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("-i", "--input", help="输入 corrected FASTA（lordec-correct 输出）")
        ps.add_argument("-o", "--output", help="输出修剪后 FASTA")
        ps.add_argument("--extra-args", help=f"透传给 lordec-{name} 的附加参数")
        _add_runtime_opts(ps, "占位：trim/trim-split 为单线程程序（不注入 -T）")

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = LordecSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LordecSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    if dry_run:
        # --dry-run 只做命令构建自检，不要求真实二进制已安装；
        # build_command 内会先按子命令设置 self.binary，此处覆写解析返回该名即可
        skill._resolve_binary = lambda: skill.binary  # type: ignore[method-assign]

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
