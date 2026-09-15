#!/usr/bin/env python3
"""sopra native 标准入口驱动（SOPRA v1.4.6；说明型）。

⚠️ DEPRECATED：本模块登记的是 SOPRA（Statistical Optimization of Paired Read
Assembly，v1.4.6；Dayarian et al. 2010, BMC Bioinformatics）。v1.4.6（2011-08）后
长期停更，文档所给 GitHub 链接（schneebergerlab/SOPRA）已 404——scaffolding 请改用
SSPACE / SOAPdenovo 内置 scaffolding / BESST / LINKS 等。

本驱动为「说明型 + 命令构造」：不实际运行 SOPRA 的 Perl 脚本（软件已淘汰、无官方
容器/conda），按官方 .pl 用法构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. prep             s_prep_contigAseq_v1.4.6.pl -contig <contig.fa> -mate <frag.fa> [<jump.fa>] -a <dir>
2. parse_sam        s_parse_sam_v1.4.6.pl -sam <sam...> -a <dir>
3. read_parsed_sam  s_read_parsed_sam_v1.4.6.pl -parsed <p1> -d <d1> [-parsed <p2> -d <d2>] -a <dir>
4. scaf             s_scaf_v1.4.6.pl -o <orientdistinfo_c5> -a <dir>

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py prep --contig contig.fasta --mate-frag frag.fasta \
       --mate-jump jump.fasta -a SOPRA_OUT
   python main.py parse_sam --sam frag_sopra.sam jump_sopra.sam -a SOPRA_OUT
   python main.py read_parsed_sam --parsed frag_sopra.sam_parsed --distance 177 \
       --parsed jump_sopra.sam_parsed --distance 3014 -a SOPRA_OUT
   python main.py scaf --orient orientdistinfo_c5 -a SOPRA_OUT
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已下载官方 SOPRA_v1.4.6.zip，解压后把 *.pl 加入 PATH；比对步骤依赖 bowtie2
（见 README「环境安装」）。
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
    "prep": "准备 contig+mate 序列（s_prep_contigAseq_v1.4.6.pl -contig -mate -a）",
    "parse_sam": "解析 bowtie2 SAM（s_parse_sam_v1.4.6.pl -sam -a）",
    "read_parsed_sam": "统计序列方向/距离（s_read_parsed_sam_v1.4.6.pl -parsed -d -a）",
    "scaf": "进行 scaffold 连接（s_scaf_v1.4.6.pl -o -a）",
}

# 子命令 → 官方 v1.4.6 Perl 脚本名
_BINARIES = {
    "prep": "s_prep_contigAseq_v1.4.6.pl",
    "parse_sam": "s_parse_sam_v1.4.6.pl",
    "read_parsed_sam": "s_read_parsed_sam_v1.4.6.pl",
    "scaf": "s_scaf_v1.4.6.pl",
}

DEPRECATED_NOTE = (
    "⚠️ SOPRA 已淘汰（v1.4.6 后停更，文档所给 GitHub 链接 404，建议用 SSPACE / "
    "SOAPdenovo 内置 scaffolding / BESST / LINKS 替代）：本模块仅作历史参考登记，"
    "以下命令构造仅供复现历史分析，新项目请勿使用。"
)


class SopraSkill(base.SkillBase):
    software = "sopra"
    binary = "s_prep_contigAseq_v1.4.6.pl"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析对应的 SOPRA .pl 脚本路径，找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行脚本 '{bin_name}'：请下载官方 SOPRA_v1.4.6.zip 解压后把 "
                f"source_codes_v1.4.6/SOPRA_with_prebuilt_contigs/*.pl 加入 PATH"
                f"（见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    @staticmethod
    def _as_list(v) -> list:
        if v is None:
            return []
        return list(v) if isinstance(v, (list, tuple)) else [v]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """prep / parse_sam / read_parsed_sam / scaf：构造（不执行）命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "prep":
            contig = kw.get("contig")
            out_dir = kw.get("out_dir")
            if not contig:
                raise RuntimeError("prep 需要 --contig（-contig 输入 contigs FASTA）")
            if not out_dir:
                raise RuntimeError("prep 需要 -a/--out-dir（分析目录）")
            mates = [m for m in self._as_list(kw.get("mate_frag")) if m]
            mates += [m for m in self._as_list(kw.get("mate_jump")) if m]
            if not mates:
                raise RuntimeError("prep 需要 --mate-frag（-mate 配对末端片段库 FASTA）")
            cmd = [bin_path, "-contig", self._abspath(contig), "-mate"]
            cmd += [self._abspath(m) for m in mates]
            cmd += ["-a", str(out_dir)]
            return cmd

        if subcommand == "parse_sam":
            sams = [s for s in self._as_list(kw.get("sam")) if s]
            out_dir = kw.get("out_dir")
            if not sams:
                raise RuntimeError("parse_sam 需要 --sam（-sam 输入 SAM，可多个）")
            if not out_dir:
                raise RuntimeError("parse_sam 需要 -a/--out-dir（分析目录）")
            cmd = [bin_path, "-sam"] + [self._abspath(s) for s in sams]
            cmd += ["-a", str(out_dir)]
            return cmd

        if subcommand == "read_parsed_sam":
            parsed = [p for p in self._as_list(kw.get("parsed")) if p]
            dists = self._as_list(kw.get("distance"))
            out_dir = kw.get("out_dir")
            if not parsed:
                raise RuntimeError("read_parsed_sam 需要 --parsed（-parsed 输入，可多个）")
            if not dists:
                raise RuntimeError("read_parsed_sam 需要 --distance（-d，与 --parsed 一一对应）")
            if len(parsed) != len(dists):
                raise RuntimeError(
                    f"read_parsed_sam 的 --parsed（{len(parsed)} 个）与 --distance"
                    f"（{len(dists)} 个）数量必须一致")
            if not out_dir:
                raise RuntimeError("read_parsed_sam 需要 -a/--out-dir（分析目录）")
            cmd = [bin_path]
            for p, d in zip(parsed, dists):
                cmd += ["-parsed", self._abspath(p), "-d", str(int(d))]
            cmd += ["-a", str(out_dir)]
            return cmd

        # scaf
        orient = kw.get("orient")
        out_dir = kw.get("out_dir")
        if not orient:
            raise RuntimeError("scaf 需要 --orient（-o 方向/距离信息前缀，如 orientdistinfo_c5）")
        if not out_dir:
            raise RuntimeError("scaf 需要 -a/--out-dir（分析目录）")
        return [bin_path, "-o", str(orient), "-a", str(out_dir)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="sopra-skill",
        description="SOPRA native 技能驱动（说明型：构造历史 v1.4.6 Perl 脚本命令，"
                    "已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("prep", help=SUBCOMMANDS["prep"])
    pp.add_argument("--contig", required=True, help="-contig 输入 contigs FASTA")
    pp.add_argument("--mate-frag", required=True, help="-mate 配对末端片段库（frag）FASTA")
    pp.add_argument("--mate-jump", help="-mate 跳步库（jump）FASTA")
    pp.add_argument("-a", "--out-dir", required=True, help="分析目录（产物目录）")
    _add_runtime_opts(pp)

    ps = sub.add_parser("parse_sam", help=SUBCOMMANDS["parse_sam"])
    ps.add_argument("--sam", nargs="+", required=True, help="-sam 输入 SAM（可多个）")
    ps.add_argument("-a", "--out-dir", required=True, help="分析目录（产物目录）")
    _add_runtime_opts(ps)

    pr = sub.add_parser("read_parsed_sam", help=SUBCOMMANDS["read_parsed_sam"])
    pr.add_argument("--parsed", action="append", required=True,
                    help="-parsed 输入 <sam>_parsed（可重复，与 --distance 一一对应）")
    pr.add_argument("--distance", "-d", action="append", type=int, required=True,
                    help="-d 对应文库插入距离（可重复）")
    pr.add_argument("-a", "--out-dir", required=True, help="分析目录（产物目录）")
    _add_runtime_opts(pr)

    pc = sub.add_parser("scaf", help=SUBCOMMANDS["scaf"])
    pc.add_argument("-o", "--orient", required=True,
                    help="-o 方向/距离信息前缀（如 orientdistinfo_c5）")
    pc.add_argument("-a", "--out-dir", required=True, help="分析目录（产物目录）")
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int,
                   help="线程数（SOPRA .pl 单线程；该值仅用于 bowtie2 比对步骤，未透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if args and args[0] == "--":
        args = args[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = SopraSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SopraSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "prep":
        print("[hint] prep 产物 contigs_sopra.fasta 需再经 bowtie2-build + bowtie2 单端"
              "比对（-p 4 -k 10），然后进入 parse_sam", file=sys.stderr)
    if ns.subcommand == "scaf":
        print("[hint] scaf 的 -o 取 read_parsed_sam 产出的 orientdistinfo_c* 前缀",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
