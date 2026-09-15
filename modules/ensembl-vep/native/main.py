#!/usr/bin/env python3
"""ensembl-vep native 标准入口驱动（Perl CLI 驱动）。

VEP 是 Perl 程序，官方调用形如：
    vep -i variants.vcf -o variants.vep.vcf --cache --cache_version 104 \\
        --species homo_sapiens --assembly GRCh38 --vcf --fork 4 --force_overwrite
    vep_install -a cf -s homo_sapiens -y GRCh38 -c ~/.vep --CONVERT
    filter_vep -i variants.vep.vcf -o filtered.vcf -f "IMPACT is HIGH"
conda（bioconda::ensembl-vep）提供 vep / vep_install / filter_vep 三个命令；官方源码
release + `perl INSTALL.pl` 亦可。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py annotate -i variants.vcf -o variants.vep.vcf --cache --species homo_sapiens \\
       --assembly GRCh38 --vcf --fork 4 --force_overwrite
   python main.py cache -a cf -s homo_sapiens -y GRCh38 -c ~/.vep --CONVERT
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 入口定位：按子命令解析 vep（annotate）/ vep_install（cache）/ filter_vep（filter）。
- annotate 的 --fork 由 --threads（默认 8）注入。
- 临时目录经 TMPDIR / PERL5LIB 注入。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "annotate": "vep：变异功能注释（Consequence / IMPACT / SIFT / PolyPhen 等）",
    "cache": "vep_install：下载/构建 VEP 缓存数据库",
    "filter": "filter_vep：对 VEP 注释结果做过滤",
}

# 子命令 -> 可执行名
_BIN_FOR = {
    "annotate": "vep",
    "cache": "vep_install",
    "filter": "filter_vep",
}


class EnsemblVepSkill(base.SkillBase):
    software = "ensembl-vep"
    binary = "vep"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令可执行名（vep / vep_install / filter_vep）惰性解析。"""
        bin_name = name or self.binary
        path = base.which(bin_name)
        if path:
            return path
        # 源码安装（INSTALL.pl）后的常见位置兜底
        cands: list[str] = []
        home = os.environ.get("ENSEMBL_VEP_HOME")
        if home:
            cands.append(str(Path(home) / bin_name))
        conda = os.environ.get("CONDA_PREFIX", "")
        if conda:
            cands += sorted(glob.glob(f"{conda}/share/ensembl-vep*/{bin_name}"))
        cands += sorted(glob.glob(str(Path("~/software").expanduser() / f"ensembl-vep*/{bin_name}")))
        for c in cands:
            if Path(c).exists():
                return c
        raise RuntimeError(
            f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 ensembl-vep"
            "（conda bioconda ensembl-vep 提供 vep / vep_install / filter_vep），或源码 "
            "release + perl INSTALL.pl"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        cmd: list[str] = [self._resolve_binary(_BIN_FOR[subcommand])]

        if subcommand == "annotate":
            if kw.get("input"):
                cmd += ["-i", str(kw["input"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("cache"):
                cmd.append("--cache")
            if kw.get("dir_cache"):
                cmd += ["--dir_cache", str(kw["dir_cache"])]
            if kw.get("cache_version") is not None:
                cmd += ["--cache_version", str(kw["cache_version"])]
            if kw.get("species"):
                cmd += ["--species", str(kw["species"])]
            if kw.get("assembly"):
                cmd += ["--assembly", str(kw["assembly"])]
            if kw.get("fasta"):
                cmd += ["--fasta", str(kw["fasta"])]
            if kw.get("merged"):
                cmd.append("--merged")
            if kw.get("vcf"):
                cmd.append("--vcf")
            elif kw.get("tab"):
                cmd.append("--tab")
            if kw.get("everything"):
                cmd.append("--everything")
            if kw.get("sift"):
                cmd += ["--sift", str(kw["sift"])]
            if kw.get("polyphen"):
                cmd += ["--polyphen", str(kw["polyphen"])]
            for key, flag in (("symbol", "--symbol"), ("protein", "--protein"),
                              ("biotype", "--biotype"), ("canonical", "--canonical"),
                              ("hgvs", "--hgvs"), ("numbers", "--numbers"),
                              ("domains", "--domains"), ("regulatory", "--regulatory"),
                              ("ccds", "--ccds"), ("uniprot", "--uniprot"),
                              ("tsl", "--tsl"), ("appris", "--appris")):
                if kw.get(key):
                    cmd.append(flag)
            cmd += ["--fork", str(self._effective_threads("annotate", kw.get("threads")))]
            if kw.get("force_overwrite"):
                cmd.append("--force_overwrite")

        elif subcommand == "cache":
            if kw.get("auto"):
                cmd += ["-a", str(kw["auto"])]
            if kw.get("species"):
                cmd += ["-s", str(kw["species"])]
            if kw.get("assembly"):
                cmd += ["-y", str(kw["assembly"])]
            if kw.get("dir_cache"):
                cmd += ["-c", str(kw["dir_cache"])]
            if kw.get("convert"):
                cmd.append("--CONVERT")

        elif subcommand == "filter":
            if kw.get("input"):
                cmd += ["-i", str(kw["input"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("filter_expr"):
                cmd += ["-f", str(kw["filter_expr"])]
            if kw.get("format"):
                cmd += ["--format", str(kw["format"])]
            if kw.get("only_matched"):
                cmd.append("--only_matched")
            if kw.get("force_overwrite"):
                cmd.append("--force_overwrite")

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（annotate 的 --fork）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ensembl-vep-skill",
        description="ensembl-vep native 技能驱动（VEP 变异注释；annotate 的 --fork 经 --threads 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # annotate
    pa = sub.add_parser("annotate", help=SUBCOMMANDS["annotate"])
    pa.add_argument("-i", "--input", help="输入 VCF")
    pa.add_argument("-o", "--output", help="输出文件")
    pa.add_argument("--cache", dest="cache", action="store_true", default=True, help="使用本地缓存（默认开）")
    pa.add_argument("--no-cache", dest="cache", action="store_false", help="关闭本地缓存（在线模式）")
    pa.add_argument("--dir_cache", dest="dir_cache", help="缓存目录")
    pa.add_argument("--cache_version", dest="cache_version", type=int, help="缓存版本（文档示例 104）")
    pa.add_argument("--species", help="物种名（如 homo_sapiens）")
    pa.add_argument("--assembly", help="参考基因组版本（如 GRCh38）")
    pa.add_argument("--fasta", help="参考 FASTA")
    pa.add_argument("--merged", action="store_true", help="使用合并缓存")
    pa.add_argument("--vcf", action="store_true", help="输出 VCF")
    pa.add_argument("--tab", action="store_true", help="输出制表符格式")
    pa.add_argument("--everything", action="store_true", help="输出全部注释")
    pa.add_argument("--sift", help="SIFT 预测（b=both）")
    pa.add_argument("--polyphen", help="PolyPhen 预测（b=both）")
    pa.add_argument("--symbol", action="store_true", help="输出基因符号")
    pa.add_argument("--protein", action="store_true", help="输出蛋白变化")
    pa.add_argument("--biotype", action="store_true", help="输出 biotype")
    pa.add_argument("--canonical", action="store_true", help="仅注释经典转录本")
    pa.add_argument("--hgvs", action="store_true", help="输出 HGVS")
    pa.add_argument("--numbers", action="store_true", help="输出外显子/内含子编号")
    pa.add_argument("--domains", action="store_true", help="输出蛋白结构域")
    pa.add_argument("--regulatory", action="store_true", help="输出调控注释")
    pa.add_argument("--ccds", action="store_true", help="输出 CCDS 注释")
    pa.add_argument("--uniprot", action="store_true", help="输出 UniProt 注释")
    pa.add_argument("--tsl", action="store_true", help="输出 TSL")
    pa.add_argument("--appris", action="store_true", help="输出 APPRIS")
    pa.add_argument("--force_overwrite", action="store_true", help="强制覆盖输出")
    pa.add_argument("--extra-args", help="透传额外参数")
    _add_runtime_opts(pa)

    # cache
    pc = sub.add_parser("cache", help=SUBCOMMANDS["cache"])
    pc.add_argument("-a", "--auto", help="vep_install AUTO 串（如 cf）")
    pc.add_argument("-s", "--species", help="物种名")
    pc.add_argument("-y", "--assembly", help="参考基因组版本")
    pc.add_argument("-c", "--dir_cache", dest="dir_cache", help="缓存目录")
    pc.add_argument("--CONVERT", dest="convert", action="store_true", help="转换缓存为当前格式")
    pc.add_argument("--extra-args", help="透传额外参数")
    _add_runtime_opts(pc)

    # filter
    pf = sub.add_parser("filter", help=SUBCOMMANDS["filter"])
    pf.add_argument("-i", "--input", help="输入 VEP 注释文件")
    pf.add_argument("-o", "--output", help="输出文件")
    pf.add_argument("-f", "--filter", dest="filter_expr", help="过滤表达式（如 'IMPACT is HIGH'）")
    pf.add_argument("--format", help="输入格式（vcf / tab）")
    pf.add_argument("--only_matched", action="store_true", help="仅输出匹配项")
    pf.add_argument("--force_overwrite", action="store_true", help="强制覆盖输出")
    pf.add_argument("--extra-args", help="透传额外参数")
    _add_runtime_opts(pf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = EnsemblVepSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EnsemblVepSkill()
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

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
