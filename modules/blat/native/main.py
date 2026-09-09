#!/usr/bin/env python3
"""blat native 标准入口驱动（UCSC BLAT v36）。

BLAT（Kent WJ, Genome Res 2002）是 UCSC 的快速 mRNA/DNA/蛋白比对工具；本模块
非 deprecated：UCSC 至今在 hgdownload 持续分发独立 blat 二进制（2026-09 直链 200）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py blat ref.fa reads.fa out.psl
   python main.py blat ref.2bit mrna.fa out.pslx -t dnax -q rnax --out-format pslx
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令形态（UCSC usage）：
  blat [-t=type] [-q=type] [-tileSize=N] [-stepSize=N] [-minScore=N]
       [-minIdentity=N] [-fastMap] [-fine] [-out=psl] <database> <query> <output>

注意：blat 为单线程程序（无 -threads 选项）——--threads 仅占位接受，不注入命令行。
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
    "blat": "BLAT 比对：<database> <query> → <output.psl>（k-mer 种子延伸，mRNA/DNA/蛋白）",
}

_BINARIES = {"blat": "blat"}

_VALID_TYPES = ("dna", "protein", "dnax", "rnax")
_VALID_OUT = ("psl", "pslx", "axt", "maf", "sim4", "wublast", "blast", "sam")


class BlatSkill(base.SkillBase):
    software = "blat"

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
                f"未找到可执行文件 '{bin_name}'：请先安装 UCSC BLAT（mamba create -n "
                f"blat-native -c conda-forge -c bioconda blat=36，或下载 hgdownload "
                f"官方二进制；见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """blat：构造（并执行）BLAT 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "blat":
            return self._build_blat(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _build_blat(self, bin_path: str, **kw) -> list[str]:
        database = kw.get("database")
        query = kw.get("query")
        output = kw.get("output")
        if not database:
            raise RuntimeError("blat 需要 <database>（目标：FASTA/.nib/.2bit 等）")
        if not query:
            raise RuntimeError("blat 需要 <query>（查询序列文件）")
        if not output:
            raise RuntimeError("blat 需要 <output>（输出文件）")

        t_type = kw.get("t_type") or "dna"
        q_type = kw.get("q_type") or "dna"
        out_format = kw.get("out_format") or "psl"
        if t_type not in _VALID_TYPES:
            raise RuntimeError(f"-t 类型必须是 {'/'.join(_VALID_TYPES)} 之一")
        if q_type not in _VALID_TYPES:
            raise RuntimeError(f"-q 类型必须是 {'/'.join(_VALID_TYPES)} 之一")
        if out_format not in _VALID_OUT:
            raise RuntimeError(f"-out 格式必须是 {'/'.join(_VALID_OUT)} 之一")

        cmd = [bin_path,
               f"-t={t_type}",
               f"-q={q_type}",
               f"-out={out_format}"]
        if kw.get("tile_size") is not None:
            cmd.append(f"-tileSize={int(kw['tile_size'])}")
        if kw.get("step_size") is not None:
            cmd.append(f"-stepSize={int(kw['step_size'])}")
        if kw.get("min_score") is not None:
            cmd.append(f"-minScore={int(kw['min_score'])}")
        if kw.get("min_identity") is not None:
            cmd.append(f"-minIdentity={int(kw['min_identity'])}")
        if kw.get("fast_map"):
            cmd.append("-fastMap")
        if kw.get("fine"):
            cmd.append("-fine")
        if kw.get("no_head"):
            cmd.append("-noHead")
        cmd += [str(database), str(query), str(output)]
        return cmd  # 输出写入 <output>（PSL/PSLX 等）


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="blat-skill",
        description="UCSC BLAT native 技能驱动（k-mer 种子延伸快速比对；单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pb = sub.add_parser("blat", help=SUBCOMMANDS["blat"])
    pb.add_argument("database", help="目标（参考）：FASTA/.nib/.2bit 文件")
    pb.add_argument("query", help="查询序列文件（FASTA/FASTQ/.nib/.2bit）")
    pb.add_argument("output", help="输出文件（PSL/PSLX，按 --out-format）")
    pb.add_argument("-t", "--t-type", dest="t_type", default="dna",
                    choices=list(_VALID_TYPES), help="-t 目标类型（默认 dna）")
    pb.add_argument("-q", "--q-type", dest="q_type", default="dna",
                    choices=list(_VALID_TYPES), help="-q 查询类型（默认 dna）")
    pb.add_argument("--out-format", dest="out_format", default="psl",
                    choices=list(_VALID_OUT), help="-out 输出格式（默认 psl）")
    pb.add_argument("--tile-size", dest="tile_size", type=int,
                    help="-tileSize=N 种子长度")
    pb.add_argument("--step-size", dest="step_size", type=int,
                    help="-stepSize=N 种子步长")
    pb.add_argument("--min-score", dest="min_score", type=int, default=30,
                    help="-minScore=N 最小比对得分（默认 30）")
    pb.add_argument("--min-identity", dest="min_identity", type=int,
                    help="-minIdentity=N 最小一致率（默认 90）")
    pb.add_argument("--fast-map", dest="fast_map", action="store_true",
                    help="-fastMap 快速近似模式")
    pb.add_argument("--fine", action="store_true", help="-fine 高精度模式")
    pb.add_argument("--no-head", dest="no_head", action="store_true",
                    help="-noHead 不打印 PSL 头部")
    _add_runtime_opts(pb)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=str, default="auto",
                   help="占位（blat 单线程，不注入命令行；auto 或正整数均接受）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = BlatSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BlatSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir",
                       "database", "query", "output") and v is not None}
    if ns.subcommand == "blat":
        kw["database"] = ns.database
        kw["query"] = ns.query
        kw["output"] = ns.output

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
