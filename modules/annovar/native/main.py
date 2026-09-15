#!/usr/bin/env python3
"""annovar native 标准入口驱动（Perl 脚本驱动）。

ANNOVAR 是一组 Perl 脚本（需在官网注册获取 annovar.latest.tar.gz 后解压，许可受限），
官方调用形如：
    perl table_annovar.pl variants.vcf humandb/ -buildver hg38 -out variants.annovar \\
        -remove -protocol refGene,1000g2015aug_all,avsnp150 -operation g,f,f \\
        -nastring . -vcfinput --otherinfo
    perl annotate_variation.pl -geneanno -buildver hg38 variants.vcf humandb/
    perl annotate_variation.pl -regionanno -buildver hg38 -dbtype cytoBand variants.vcf humandb/
    perl annotate_variation.pl -filter -buildver hg38 -dbtype 1000g2015aug_all -maf 0.01 variants.vcf humandb/
    perl annotate_variation.pl -downdb -buildver hg38 -webfrom annovar refGene humandb/

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py table_annovar variants.vcf humandb/ -buildver hg38 -out variants.annovar \\
       -remove -protocol refGene,1000g2015aug_all,avsnp150 -operation g,f,f -nastring . \\
       -vcfinput --otherinfo
   python main.py downdb -buildver hg38 -dbtype refGene -webfrom annovar humandb/
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 入口定位：优先 ANNOVAR_HOME 环境变量（解压后的 annovar 目录），其次 conda share/bin、
  ~/software/annovar*，最后 PATH；统一以 `perl <script>` 调用（脚本无需可执行位）。
- table_annovar 支持 -thread（--threads 覆盖），其余子命令单线程。
- 临时目录经 TMPDIR 注入。
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
    "table_annovar": "table_annovar.pl：一次性多数据库注释（gene/region/filter）",
    "geneanno": "annotate_variation.pl -geneanno：基于基因的注释",
    "regionanno": "annotate_variation.pl -regionanno：基于区域的注释",
    "filter": "annotate_variation.pl -filter：基于数据库的过滤注释",
    "downdb": "annotate_variation.pl -downdb：下载 ANNOVAR 注释数据库",
}

# 子命令 -> 脚本名
_SCRIPT_FOR = {
    "table_annovar": "table_annovar.pl",
    "geneanno": "annotate_variation.pl",
    "regionanno": "annotate_variation.pl",
    "filter": "annotate_variation.pl",
    "downdb": "annotate_variation.pl",
}
_MODE_FLAG = {"geneanno": "-geneanno", "regionanno": "-regionanno", "filter": "-filter"}


class AnnovarSkill(base.SkillBase):
    software = "annovar"
    binary = "table_annovar.pl"

    # -- 入口定位 --------------------------------------------------------- #
    def _resolve_binary(self, name: str | None = None) -> str:
        """按脚本名惰性解析 ANNOVAR Perl 脚本绝对路径。"""
        bin_name = name or self.binary
        cands: list[Path] = []
        home = os.environ.get("ANNOVAR_HOME")
        if home:
            cands += [Path(home) / bin_name, Path(home) / "annovar" / bin_name]
        conda = os.environ.get("CONDA_PREFIX", "")
        if conda:
            cands += [Path(conda) / "bin" / bin_name]
            cands += [Path(p) for p in glob.glob(f"{conda}/share/annovar*/{bin_name}")]
            cands += [Path(p) for p in glob.glob(f"{conda}/share/annovar*/bin/{bin_name}")]
        cands += [Path(p) for p in glob.glob(str(Path("~/software").expanduser() / f"annovar*/{bin_name}"))]
        for c in cands:
            if c.exists():
                return str(c)
        path = base.which(bin_name)
        if path:
            return path
        raise RuntimeError(
            f"未找到 ANNOVAR 脚本 '{bin_name}'：官方渠道无镜像/conda；请在官网注册下载 "
            "annovar.latest.tar.gz 解压后导出 ANNOVAR_HOME=/path/to/annovar，或按 native/Dockerfile "
            "/ Apptainer.def 自建容器"
        )

    def _perl(self) -> str:
        return base.which("perl") or "perl"

    # -- 命令构建 --------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        script = self._resolve_binary(_SCRIPT_FOR[subcommand])
        cmd: list[str] = [self._perl(), script]

        if subcommand == "table_annovar":
            inp = kw.get("input")
            db_dir = kw.get("db_dir")
            if not inp or not db_dir:
                raise ValueError("table_annovar 需要 input（VCF/avinput）与 db_dir（humandb/）")
            cmd += [str(inp), str(db_dir)]
            if kw.get("buildver"):
                cmd += ["-buildver", str(kw["buildver"])]
            if kw.get("out"):
                cmd += ["-out", str(kw["out"])]
            if kw.get("remove"):
                cmd.append("-remove")
            if kw.get("protocol"):
                cmd += ["-protocol", str(kw["protocol"])]
            if kw.get("operation"):
                cmd += ["-operation", str(kw["operation"])]
            if kw.get("nastring") is not None:
                cmd += ["-nastring", str(kw["nastring"])]
            if kw.get("vcfinput"):
                cmd.append("-vcfinput")
            if kw.get("otherinfo"):
                cmd.append("--otherinfo")
            threads = self._effective_threads("table_annovar", kw.get("threads"))
            if threads > 1:
                cmd += ["-thread", str(threads)]

        elif subcommand in _MODE_FLAG:
            inp = kw.get("input")
            db_dir = kw.get("db_dir")
            if not inp or not db_dir:
                raise ValueError(f"{subcommand} 需要 input（VCF/avinput）与 db_dir（注释库目录）")
            cmd.append(_MODE_FLAG[subcommand])
            if kw.get("buildver"):
                cmd += ["-buildver", str(kw["buildver"])]
            if kw.get("dbtype"):
                cmd += ["-dbtype", str(kw["dbtype"])]
            if subcommand == "filter" and kw.get("maf") is not None:
                cmd += ["-maf", str(kw["maf"])]
            if kw.get("out"):
                cmd += ["-out", str(kw["out"])]
            if kw.get("nastring") is not None:
                cmd += ["-nastring", str(kw["nastring"])]
            cmd += [str(inp), str(db_dir)]

        elif subcommand == "downdb":
            dbtype = kw.get("dbtype")
            db_dir = kw.get("db_dir")
            if not dbtype or not db_dir:
                raise ValueError("downdb 需要 dbtype（数据库名）与 db_dir（下载目录）")
            cmd.append("-downdb")
            if kw.get("buildver"):
                cmd += ["-buildver", str(kw["buildver"])]
            if kw.get("webfrom"):
                cmd += ["-webfrom", str(kw["webfrom"])]
            cmd += [str(dbtype), str(db_dir)]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（table_annovar 的 -thread）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="annovar-skill",
        description="annovar native 技能驱动（Perl 脚本；需官网注册获取下载链接，许可受限）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # table_annovar
    pt = sub.add_parser("table_annovar", help=SUBCOMMANDS["table_annovar"])
    pt.add_argument("input", help="输入 VCF/avinput")
    pt.add_argument("db_dir", help="注释数据库目录（如 humandb/）")
    pt.add_argument("-buildver", "--buildver", help="参考基因组版本（hg19/hg38/...）")
    pt.add_argument("-out", "--out", dest="out", help="输出文件前缀")
    pt.add_argument("-protocol", "--protocol", help="注释数据库列表（逗号分隔）")
    pt.add_argument("-operation", "--operation", help="注释类型列表（g/gx/r/f，逗号分隔）")
    pt.add_argument("-nastring", "--nastring", help="缺失值占位符（文档示例 .）")
    pt.add_argument("-remove", "--remove", dest="remove", action="store_true", help="删除中间文件")
    pt.add_argument("-vcfinput", "--vcfinput", dest="vcfinput", action="store_true", help="输入为 VCF")
    pt.add_argument("--otherinfo", dest="otherinfo", action="store_true", help="保留 VCF 其他 INFO")
    pt.add_argument("--extra-args", help="透传额外参数")
    _add_runtime_opts(pt)

    # geneanno / regionanno / filter
    for name in ("geneanno", "regionanno", "filter"):
        pm = sub.add_parser(name, help=SUBCOMMANDS[name])
        pm.add_argument("input", help="输入 VCF/avinput")
        pm.add_argument("db_dir", help="注释数据库目录（如 humandb/）")
        pm.add_argument("-buildver", "--buildver", help="参考基因组版本")
        pm.add_argument("-dbtype", "--dbtype", help="注释数据库类型")
        if name == "filter":
            pm.add_argument("-maf", "--maf", type=float, help="次要等位频率阈值（文档示例 0.01）")
        pm.add_argument("-out", "--out", dest="out", help="输出文件前缀")
        pm.add_argument("-nastring", "--nastring", help="缺失值占位符")
        pm.add_argument("--extra-args", help="透传额外参数")
        _add_runtime_opts(pm)

    # downdb
    pd = sub.add_parser("downdb", help=SUBCOMMANDS["downdb"])
    pd.add_argument("dbtype", help="要下载的数据库名（如 refGene / avsnp150）")
    pd.add_argument("db_dir", help="下载目录（如 humandb/）")
    pd.add_argument("-buildver", "--buildver", help="参考基因组版本")
    pd.add_argument("-webfrom", "--webfrom", help="下载来源（annovar / UCSC）")
    pd.add_argument("--extra-args", help="透传额外参数")
    _add_runtime_opts(pd)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = AnnovarSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AnnovarSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "out") and v is not None}
    # -out 是脚本参数（输出前缀），需保留
    if getattr(ns, "out", None) is not None:
        kw["out"] = ns.out
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
