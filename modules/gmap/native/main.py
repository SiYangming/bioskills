#!/usr/bin/env python3
"""gmap native 标准入口驱动（GMAP/GSNAP 套件）。

GMAP（Wu & Watanabe, Bioinformatics 2005）把 mRNA/EST/全长转录本剪接感知地比对到
基因组；GSNAP（Wu & Nacu, Bioinformatics 2010）做 SNP/indel 容忍的短读比对。本模块
非 deprecated：官方（research-pub.gene.com）持续维护，bioconda 有 gmap。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py gmap_build -d genome genome.fa
   python main.py gmap -D . -d genome -t 8 -f samse mrna.fa
   python main.py gsnap -D . -d genome -t 8 reads_1.fq reads_2.fq
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令形态（官方 manual）：
  gmap_build [-D <dir>] -d <dbname> [--gunzip] <genome.fasta>
  gmap       -D <dir> -d <dbname> [-t N] [-f samse|sampe|...] [-n N] <reads...>
  gsnap      -D <dir> -d <dbname> [-t N] [-A sam] [-n N] <reads...>
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

SUBCOMMANDS = {
    "gmap_build": "基因组 FASTA → GMAP 数据库（-D <dir> -d <dbname>）",
    "gmap": "mRNA/EST/长读剪接感知比对（-f samse/sampe/bed 等）",
    "gsnap": "短读 SNP/indel 容忍比对（-A sam 输出 SAM）",
}

_BINARIES = {"gmap_build": "gmap_build", "gmap": "gmap", "gsnap": "gsnap"}

GMAP_FORMATS = ("samse", "sampe", "bed", "gff3_gene", "gff3_match", "splicesites")
GSNAP_FORMATS = ("sam",)


class GmapSkill(base.SkillBase):
    software = "gmap"

    def __init__(self, meta_path: str | Path | None = None):
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 GMAP/GSNAP（mamba create -n "
                f"gmap-native -c conda-forge -c bioconda gmap=2025.07.31，或官方源码"
                f"make；见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """gmap_build / gmap / gsnap：构造（并执行）GMAP/GSNAP 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "gmap_build":
            return self._build_gmap_build(bin_path, **kw)
        if subcommand == "gmap":
            return self._build_gmap(bin_path, **kw)
        if subcommand == "gsnap":
            return self._build_gsnap(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- gmap_build -------------------------------------------------------- #
    def _build_gmap_build(self, bin_path: str, **kw) -> list[str]:
        reference = kw.get("reference")
        db_name = kw.get("db_name")
        if not reference:
            raise RuntimeError("gmap_build 需要参考基因组 FASTA（位置参数）")
        if not db_name:
            raise RuntimeError("gmap_build 需要 --db-name（-d <dbname>）")

        cmd = [bin_path,
               "-D", str(kw.get("db_dir") or "."),
               "-d", str(db_name)]
        if kw.get("gunzip"):
            cmd.append("--gunzip")
        cmd.append(str(reference))
        return cmd  # 产物 <db_dir>/<db_name>/ 数据库目录

    # -- gmap -------------------------------------------------------------- #
    def _build_gmap(self, bin_path: str, **kw) -> list[str]:
        db_name = kw.get("db_name")
        reads = kw.get("reads") or []
        read_list = [reads] if isinstance(reads, str) else [r for r in reads if r]
        if not db_name:
            raise RuntimeError("gmap 需要 --db-name（-d <dbname>，gmap_build 建好的库）")
        if not read_list:
            raise RuntimeError("gmap 需要至少一个 reads 文件（位置参数）")

        cmd = [bin_path,
               "-D", str(kw.get("db_dir") or "."),
               "-d", str(db_name)]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-t", str(int(threads))]
        else:
            cmd += ["-t", "4"]
        if kw.get("format"):
            fmt = kw["format"]
            if fmt not in GMAP_FORMATS:
                raise RuntimeError(f"-f 输出格式必须是 {'/'.join(GMAP_FORMATS)} 之一")
            cmd += ["-f", fmt]
        if kw.get("npaths") is not None:
            cmd += ["-n", str(int(kw["npaths"]))]
        for r in read_list:
            cmd.append(str(r))
        return cmd

    # -- gsnap ------------------------------------------------------------- #
    def _build_gsnap(self, bin_path: str, **kw) -> list[str]:
        db_name = kw.get("db_name")
        reads = kw.get("reads") or []
        read_list = [reads] if isinstance(reads, str) else [r for r in reads if r]
        if not db_name:
            raise RuntimeError("gsnap 需要 --db-name（-d <dbname>，gmap_build 建好的库）")
        if not read_list:
            raise RuntimeError("gsnap 需要至少一个 reads 文件（位置参数）")

        cmd = [bin_path,
               "-D", str(kw.get("db_dir") or "."),
               "-d", str(db_name)]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-t", str(int(threads))]
        else:
            cmd += ["-t", "4"]
        if kw.get("sam"):
            cmd += ["-A", "sam"]
        if kw.get("npaths") is not None:
            cmd += ["-n", str(int(kw["npaths"]))]
        for r in read_list:
            cmd.append(str(r))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gmap-skill",
        description="GMAP/GSNAP native 技能驱动（GMAP/GSNAP 套件；剪接感知比对）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pb = sub.add_parser("gmap_build", help=SUBCOMMANDS["gmap_build"])
    pb.add_argument("reference", help="参考基因组 FASTA（.gz 时加 --gunzip）")
    pb.add_argument("-D", "--db-dir", dest="db_dir", default=".",
                    help="-D 数据库目录（默认当前目录）")
    pb.add_argument("-d", "--db-name", dest="db_name", required=True,
                    help="-d 数据库名（建库名；GMAP 比对时用同名 -d）")
    pb.add_argument("--gunzip", action="store_true",
                    help="输入参考为 gzip 压缩（--gunzip）")
    _add_runtime_opts(pb)

    pg = sub.add_parser("gmap", help=SUBCOMMANDS["gmap"])
    pg.add_argument("reads", nargs="+", help="reads 文件（mRNA/EST/长读 FASTQ/FASTA）")
    pg.add_argument("-D", "--db-dir", dest="db_dir", default=".",
                    help="-D 数据库目录（默认当前目录）")
    pg.add_argument("-d", "--db-name", dest="db_name", required=True,
                    help="-d 数据库名")
    pg.add_argument("-f", "--format", dest="format", default=None,
                    choices=list(GMAP_FORMATS),
                    help="-f 输出格式（samse/sampe/bed/...；默认 gmap 原生坐标）")
    pg.add_argument("-n", "--npaths", dest="npaths", type=int,
                    help="每 read 报告比对路径数（默认 5）")
    _add_runtime_opts(pg)

    pgs = sub.add_parser("gsnap", help=SUBCOMMANDS["gsnap"])
    pgs.add_argument("reads", nargs="+", help="短读文件（FASTQ/FASTA；双端给两个文件）")
    pgs.add_argument("-D", "--db-dir", dest="db_dir", default=".",
                    help="-D 数据库目录（默认当前目录）")
    pgs.add_argument("-d", "--db-name", dest="db_name", required=True,
                    help="-d 数据库名")
    pgs.add_argument("-A", "--sam", dest="sam", action="store_true",
                    help="输出 SAM（-A sam）")
    pgs.add_argument("-n", "--npaths", dest="npaths", type=int,
                    help="每 read 报告比对路径数（默认 5）")
    _add_runtime_opts(pgs)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，gmap/gsnap -t）或 auto（默认 -t 4）。"""
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
                   help="线程数：auto（默认，-t 4）或正整数（gmap/gsnap -t N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GmapSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GmapSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir",
                       "reads", "reference") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "gmap_build":
        kw["reference"] = ns.reference
    else:
        kw["reads"] = ns.reads

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
