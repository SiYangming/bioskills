#!/usr/bin/env python3
"""stampy native 标准入口驱动（Stampy 1.0.32；说明型）。

⚠️ DEPRECATED：本模块登记的是 Stampy（Lunter & Goodson, Genome Res 2011），
高灵敏 Illumina 短读比对器（15-mer hash + gapped aligner + 概率 realigner）。
1.0.32 之后基本停更（官方 tgz 2017-11-06），强依赖 Python 2.7，官方下载点已迁移/
不可直连——建议改用 BWA-MEM / Bowtie2 / Novoalign。

本驱动为「说明型 + 命令构造」：不实际运行 stampy.py（软件 deprecated、需 Python2
环境），按官方 help 构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. genome：建基因组索引
   stampy.py -G <prefix> <ref.fa> [--species=S --assembly=S]
   → 产物 <prefix>.stidx
2. hash：建 hash 索引（依赖 genome 产物）
   stampy.py -g <prefix> -H <prefix> [--maxcount=N]
   → 产物 <prefix>.sthash
3. map：比对 reads → SAM
   stampy.py -g <prefix> -h <prefix> -M <reads.fq[,reads2.fq]> [-o out.sam]
            [-f sam] [-t threads] [--sensitive] [--substitutionrate=F]

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py genome genome --species human --assembly hg19 ref.fa
   python main.py hash genome --maxcount 200
   python main.py map --genome-prefix genome --hash-prefix genome \
       -M reads_1.fq,reads_2.fq -o out.sam --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已部署 Stampy 1.0.32（stampy.py 在 PATH；运行需 Python 2.7 与编译好的
maptools 扩展，见 README「环境安装」）。本驱动不执行真实比对（仅命令构造）。
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
    "genome": "stampy.py -G：参考 FASTA → 基因组索引 PREFIX.stidx（命令构造；仅历史复现）",
    "hash": "stampy.py -g -H：→ hash 索引 PREFIX.sthash（命令构造；仅历史复现）",
    "map": "stampy.py -g -h -M：reads → SAM 比对（命令构造；仅历史复现）",
}

# 三个动作都由 stampy.py 承担（PATH 中需能找到 stampy.py）
_BINARIES = {"genome": "stampy.py", "hash": "stampy.py", "map": "stampy.py"}

DEPRECATED_NOTE = (
    "⚠️ Stampy 已淘汰（1.0.32 后停更、依赖 Python 2.7、官方下载点不可直连，建议用 "
    "BWA-MEM / Bowtie2 / Novoalign 替代）：本模块仅作历史参考登记，以下命令构造仅供"
    "复现历史分析，新项目请勿使用。"
)

# 子命令描述（--list-commands 用）里的可选说明
FORMATS = ("sam", "maqtxt", "maqmap", "maqmapN")


class StampySkill(base.SkillBase):
    software = "stampy"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（stampy.py），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先部署 Stampy 1.0.32 并把 stampy.py "
                f"所在目录加入 PATH（源码可取自镜像如 github.com/uwb-linux/stampy，"
                f"见 README「环境安装」；运行需 Python 2.7）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """genome / hash / map：构造（不执行）历史 stampy.py 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "genome":
            return self._build_genome(bin_path, **kw)
        if subcommand == "hash":
            return self._build_hash(bin_path, **kw)
        if subcommand == "map":
            return self._build_map(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- genome ------------------------------------------------------------ #
    def _build_genome(self, bin_path: str, **kw) -> list[str]:
        prefix = kw.get("prefix")
        refs = kw.get("reference") or []
        ref_list = [refs] if isinstance(refs, str) else [r for r in refs if r]
        if not prefix:
            raise RuntimeError("genome 需要 --prefix（-G PREFIX，产物 PREFIX.stidx）")
        if not ref_list:
            raise RuntimeError("genome 需要 --reference（参考 FASTA，.fa[.gz]，可多个）")

        cmd = [bin_path, "-G", str(prefix)]
        for r in ref_list:
            cmd.append(self._abspath(r))
        if kw.get("species"):
            cmd += ["--species", str(kw["species"])]
        if kw.get("assembly"):
            cmd += ["--assembly", str(kw["assembly"])]
        return cmd  # 产物 PREFIX.stidx

    # -- hash -------------------------------------------------------------- #
    def _build_hash(self, bin_path: str, **kw) -> list[str]:
        prefix = kw.get("prefix")
        if not prefix:
            raise RuntimeError("hash 需要 --prefix（-g/-H PREFIX，产物 PREFIX.sthash）")
        cmd = [bin_path, "-g", str(prefix), "-H", str(prefix)]
        if kw.get("maxcount") is not None:
            cmd += ["--maxcount", str(int(kw["maxcount"]))]
        return cmd  # 依赖 -g 的 PREFIX.stidx 存在

    # -- map --------------------------------------------------------------- #
    def _build_map(self, bin_path: str, **kw) -> list[str]:
        genome_prefix = kw.get("genome_prefix")
        hash_prefix = kw.get("hash_prefix")
        reads = kw.get("reads")
        if not genome_prefix:
            raise RuntimeError("map 需要 --genome-prefix（-g PREFIX，PREFIX.stidx）")
        if not hash_prefix:
            raise RuntimeError("map 需要 --hash-prefix（-h PREFIX，PREFIX.sthash）")
        if not reads:
            raise RuntimeError("map 需要 --reads（-M FILE，双端逗号两文件）")

        cmd = [bin_path,
               "-g", str(genome_prefix),
               "-h", str(hash_prefix),
               "-M", str(reads)]
        if kw.get("output"):
            cmd += ["-o", self._abspath(kw["output"])]
        fmt = kw.get("output_format") or "sam"
        if fmt not in FORMATS:
            raise RuntimeError(f"-f 输出格式必须是 {'/'.join(FORMATS)} 之一")
        cmd += ["-f", fmt]
        if kw.get("sensitive"):
            cmd.append("--sensitive")
        if kw.get("substitution_rate") is not None:
            cmd += ["--substitutionrate", str(kw["substitution_rate"])]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-t", str(int(threads))]
        return cmd  # 输出 SAM（-o 或 stdout）


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="stampy-skill",
        description="Stampy native 技能驱动（说明型：构造历史 stampy.py -G/-H/-M "
                    "命令，已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pg = sub.add_parser("genome", help=SUBCOMMANDS["genome"])
    pg.add_argument("prefix", help="-G PREFIX 基因组索引前缀（产物 PREFIX.stidx）")
    pg.add_argument("reference", nargs="+", help="参考基因组 FASTA（.fa[.gz]，可多个）")
    pg.add_argument("--species", help="物种标识（--species=S，SAM @SQ SP tag）")
    pg.add_argument("--assembly", help="组装标识（--assembly=S，SAM @SQ AS tag）")
    _add_runtime_opts(pg)

    ph = sub.add_parser("hash", help=SUBCOMMANDS["hash"])
    ph.add_argument("prefix", help="-g/-H PREFIX（依赖 genome 的 PREFIX.stidx）")
    ph.add_argument("--maxcount", type=int,
                    help="(-H) 重复 word 最大拷贝数（--maxcount=N，默认 200）")
    _add_runtime_opts(ph)

    pm = sub.add_parser("map", help=SUBCOMMANDS["map"])
    pm.add_argument("--genome-prefix", "-g", required=True, dest="genome_prefix",
                    help="-g PREFIX 基因组索引前缀（PREFIX.stidx）")
    pm.add_argument("--hash-prefix", required=True, dest="hash_prefix",
                    help="-h PREFIX hash 索引前缀（PREFIX.sthash）")
    pm.add_argument("--reads", "-M", required=True,
                    help="-M 输入 reads（FASTQ/FASTA/BAM；双端逗号两文件）")
    pm.add_argument("--output", "-o", help="输出文件（默认 stdout）")
    pm.add_argument("--output-format", "-f", default="sam",
                    choices=list(FORMATS), help="-f 输出格式（默认 sam）")
    pm.add_argument("--sensitive", action="store_true",
                    help="--sensitive 更敏感模式（约慢 25-50%）")
    pm.add_argument("--substitution-rate", dest="substitution_rate", type=float,
                    help="--substitutionrate=F（默认 0.001）")
    _add_runtime_opts(pm)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，map -t N）或 auto（不传）。"""
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
                   help="线程数：auto（默认，不传）或正整数（map -t N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = StampySkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = StampySkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "prefix", "reference")
          and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "genome":
        kw["prefix"] = ns.prefix
        kw["reference"] = ns.reference
    elif ns.subcommand == "hash":
        kw["prefix"] = ns.prefix

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "genome":
        print(f"[hint] 产物 <prefix>.stidx；实际运行需 Python 2.7（python2 {' '.join(cmd)}）",
              file=sys.stderr)
    elif ns.subcommand == "hash":
        print(f"[hint] 产物 <prefix>.sthash；依赖 genome 子命令的 .stidx",
              file=sys.stderr)
    else:
        print(f"[hint] map 建议配合 BWA 的 hybrid 用法（历史流程）；输出 SAM（-o 或 stdout）",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
