#!/usr/bin/env python3
"""soap2 native 标准入口驱动（SOAPaligner/SOAP2 2.21；说明型）。

⚠️ DEPRECATED：本模块登记的是 SOAPaligner/SOAP2（soap2.21release，华大 BGI 的
2way-BWT 短读比对器；Li R et al. Bioinformatics 2009）。BGI 官网 soap.genomics.org.cn
2026-09 已不可达，soap2.21release 后长期停更——短读比对请改用 BWA / Bowtie2。

本驱动为「说明型 + 命令构造」：不实际运行 SOAP2 二进制（软件已淘汰、官网停服），
按官方 man page 构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. 2bwt-builder：参考 FASTA → 2way-BWT 索引
   2bwt-builder <ref.fasta>
   （索引文件生成在 FASTA 同目录：<ref>.bwt/.amb/.ann/.pac）
2. soap：SE/PE 短读比对
   soap -D <index> -a <reads.fa> [-b <reads2.fa>] -o <out> [-2 <unpaired>]
        [-m 400] [-x 600] [-n 5] [-r 1] [-l 256] [-v 5] [-g 0] [-M 4] [-p threads]

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py 2bwt-builder ref.fa
   python main.py soap --index ref.fa -a reads_1.fa -b reads_2.fa -o lib1.soap
       --min-insert 200 --max-insert 600 --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 SOAPaligner 2.21（soap / 2bwt-builder 在 PATH，bioconda soapaligner=2.21
或 GigaScience 存档二进制，见 README「环境安装」）。二进制无 --version 旗标，
本驱动也不执行真实比对（仅命令构造）。
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

SUBCOMMANDS = {
    "2bwt-builder": "参考 FASTA → 2way-BWT 索引（命令构造；仅历史复现）",
    "soap": "SE/PE 短读比对命令构造（-D index -a/-b reads -o out；已废弃，仅供历史参考）",
}

# 子命令 → 真实可执行名（soap2.21release 下即此名）
_BINARIES = {"2bwt-builder": "2bwt-builder", "soap": "soap"}

DEPRECATED_NOTE = (
    "⚠️ SOAPaligner/SOAP2 已淘汰（soap2.21release 后停更，BGI 官网已停服，建议用 "
    "BWA / Bowtie2 替代）：本模块仅作历史参考登记，以下命令构造仅供复现历史分析，"
    "新项目请用 BWA / Bowtie2。"
)


class Soap2Skill(base.SkillBase):
    software = "soap2"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（soap / 2bwt-builder），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 SOAPaligner 2.21 并把其目录加入 "
                f"PATH（mamba create -n soap2-native -c conda-forge -c bioconda "
                f"soapaligner=2.21，或取 GigaScience 存档二进制；见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """2bwt-builder / soap：构造（不执行）历史 SOAP2 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "2bwt-builder":
            return self._build_index(bin_path, **kw)
        if subcommand == "soap":
            return self._build_soap(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- 2bwt-builder ------------------------------------------------------ #
    def _build_index(self, bin_path: str, **kw) -> list[str]:
        reference = kw.get("reference")
        if not reference:
            raise RuntimeError("2bwt-builder 需要参考 FASTA（位置参数）")
        return [bin_path, self._abspath(reference)]
        # 产物：<ref>.bwt/.amb/.ann/.pac 生成在 FASTA 同目录（CLI 层给 hint）

    # -- soap -------------------------------------------------------------- #
    def _build_soap(self, bin_path: str, **kw) -> list[str]:
        index = kw.get("index")
        reads_a = kw.get("reads_a")
        output = kw.get("output")
        if not index:
            raise RuntimeError("soap 需要 --index（-D 参考索引前缀，2bwt-builder 产物）")
        if not reads_a:
            raise RuntimeError("soap 需要 --reads-a（-a SE reads 或 PE read1）")
        if not output:
            raise RuntimeError("soap 需要 --output（-o 比对结果文件）")

        cmd = [bin_path,
               "-D", str(index),
               "-a", self._abspath(reads_a)]
        if kw.get("reads_b"):
            cmd += ["-b", self._abspath(kw["reads_b"])]
        cmd += ["-o", self._abspath(output)]
        if kw.get("unpaired_out"):
            cmd += ["-2", self._abspath(kw["unpaired_out"])]
        cmd += ["-m", str(int(kw.get("min_insert") or 400))]
        cmd += ["-x", str(int(kw.get("max_insert") or 600))]
        cmd += ["-n", str(int(kw.get("filter_ns") or 5))]
        cmd += ["-r", str(int(kw.get("repeat_mode") or 1))]
        cmd += ["-l", str(int(kw.get("seed_length") or 256))]
        cmd += ["-v", str(int(kw.get("mismatches") or 5))]
        cmd += ["-g", str(int(kw.get("gaps") or 0))]
        cmd += ["-M", str(int(kw.get("match_mode") or 4))]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-p", str(int(threads))]
        return cmd  # 输出 SOAP 自定义格式（转 SAM 需 soap2sam）


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="soap2-skill",
        description="SOAPaligner/SOAP2 native 技能驱动（说明型：构造历史 soap/2bwt-builder "
                    "命令，已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pi = sub.add_parser("2bwt-builder", help=SUBCOMMANDS["2bwt-builder"])
    pi.add_argument("reference", help="参考基因组 FASTA（索引产物在 FASTA 同目录）")
    _add_runtime_opts(pi)

    ps = sub.add_parser("soap", help=SUBCOMMANDS["soap"])
    ps.add_argument("--index", "-D", required=True,
                    help="参考索引前缀名（2bwt-builder 产物，如 ref.fa）")
    ps.add_argument("--reads-a", "-a", required=True,
                    help="SE reads 或 PE read1（FASTA/FASTQ）")
    ps.add_argument("--reads-b", "-b", help="PE read2（省略则单端比对）")
    ps.add_argument("--output", "-o", required=True, help="比对结果文件（SOAP 格式）")
    ps.add_argument("--unpaired-out", "-2", help="PE 中 mapped-but-unpaired reads 输出")
    ps.add_argument("--min-insert", "-m", type=int, default=400,
                    help="PE 最小插入片段 bp（默认 400）")
    ps.add_argument("--max-insert", "-x", type=int, default=600,
                    help="PE 最大插入片段 bp（默认 600）")
    ps.add_argument("--filter-ns", "-n", type=int, default=5,
                    help="过滤含超过 n 个 N 的低质量 reads（默认 5）")
    ps.add_argument("--repeat-mode", "-r", type=int, default=1,
                    help="重复 hits：0=不报；1=随机一个；2=全部（默认 1）")
    ps.add_argument("--seed-length", "-l", type=int, default=256,
                    help="3' 端种子长度（默认 256=全长比对）")
    ps.add_argument("--mismatches", "-v", type=int, default=5,
                    help="单条 read 允许错配总数（默认 5）")
    ps.add_argument("--gaps", "-g", type=int, default=0, help="允许 gap 数（默认 0）")
    ps.add_argument("--match-mode", "-M", type=int, default=4,
                    help="匹配模式：0/1/2/4（默认 4=找最佳 hits）")
    _add_runtime_opts(ps)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，soap -p）或 auto（不传）。"""
    v = str(value).strip().lower()
    if v == "auto":
        return "auto"
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=_threads_arg, default=None,
                   help="线程数：auto（默认，不传）或正整数（soap -p threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Soap2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Soap2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "reference") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "2bwt-builder":
        kw["reference"] = ns.reference

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    # 2bwt-builder：索引产物提示（仅记录不执行）
    if ns.subcommand == "2bwt-builder":
        print(f"[hint] 2bwt-builder 在参考 FASTA 同目录生成 <ref>.bwt/.amb/.ann/.pac"
              f"（2way-BWT 索引），soap -D 前缀即该 FASTA 路径", file=sys.stderr)
    # soap：SOAP 格式转换提示
    if ns.subcommand == "soap":
        print(f"[hint] 产物为 SOAP 自定义格式；转 SAM 需 soap2sam（官方渠道已停服，"
              f"见 README「版本/历史留存」如实说明）", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
