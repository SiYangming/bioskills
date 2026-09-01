#!/usr/bin/env python3
"""orfanage native 标准入口驱动。

迁移自 flrnaseq.smk/orfrange_archive/orfanage.py（原 Snakemake wrapper）：
  orfanage --query <query.gff3> --output <out.gtf> [flags] [--reference REF] <templates...>

支持：
  python main.py run --query X.gff3 --output out.gtf --reference ref.fa tpl1.fa [tpl2.fa ...]
  python main.py --schema | --list-commands
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {"run": "ORFanage 主流程：按模板合并/注释预测 ORF（GFF3 -> GTF）"}

# 布尔开关 -> CLI 参数
BOOL_FLAGS = {
    "cleanq": "--cleanq",
    "cleant": "--cleant",
    "rescue": "--rescue",
    "use_id": "--use-id",
    "non_aug": "--non-aug",
    "keep_all_cds": "--keep-all-cds",
    "keep_cds_if_not_found": "--keep-cds-if-not-found",
    "spliced_overhang": "--spliced-overhang",
}


class OrfanageSkill(base.SkillBase):
    software = "orfanage"
    binary = "orfanage"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        binary = self._resolve_binary()
        query = kw.get("query")
        if not query:
            raise RuntimeError("ORFanage 需要 --query（预测的 GFF3 文件）")
        output = kw.get("output") or "orfanage.gtf"

        cmd: list[str] = [binary, "--query", str(query), "--output", str(output)]

        # 布尔开关
        for k, flag in BOOL_FLAGS.items():
            if kw.get(k):
                cmd.append(flag)

        # 数值/字符串参数
        if kw.get("lpi") is not None and kw["lpi"] != -1:
            cmd += ["--lpi", str(kw["lpi"])]
        if kw.get("ilpi") is not None and kw["ilpi"] != -1:
            cmd += ["--ilpi", str(kw["ilpi"])]
        if kw.get("mlpi") is not None and kw["mlpi"] != -1:
            cmd += ["--mlpi", str(kw["mlpi"])]
        if kw.get("minlen"):
            cmd += ["--minlen", str(kw["minlen"])]
        if kw.get("mode"):
            cmd += ["--mode", str(kw["mode"])]
        if kw.get("stats"):
            cmd += ["--stats", str(kw["stats"])]
        if kw.get("overhang"):
            cmd += ["--overhang", str(kw["overhang"])]

        threads = kw.get("threads") or self.cpus
        cmd += ["--threads", str(threads)]

        # 参考序列
        if kw.get("reference"):
            cmd += ["--reference", str(kw["reference"])]

        # 模板位置参数
        tpls = kw.get("templates") or []
        if isinstance(tpls, str):
            tpls = [tpls]
        if not tpls:
            raise RuntimeError("ORFanage 至少需要一个模板文件（FASTA，如参考转录本）")
        cmd += [str(t) for t in tpls]

        # 高级透传
        if kw.get("extra_args"):
            cmd += str(kw["extra_args"]).split()
        return cmd


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="orfanage-skill",
        description="orfanage native 技能驱动（按模板合并/注释预测 ORF）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("--query", required=True, help="预测 GFF3（如 *.transdecoder.gff3）")
    pr.add_argument("--output", help="输出 GTF（默认 orfanage.gtf）")
    pr.add_argument("--reference", help="参考序列 FASTA")
    pr.add_argument("templates", nargs="+", help="一个或多个模板 FASTA（参考转录本/直系同源）")
    for k, flag in BOOL_FLAGS.items():
        pr.add_argument(f"--{k.replace('_', '-')}", action="store_true", dest=k,
                        help=f"布尔开关 {flag}")
    pr.add_argument("--lpi", type=int, default=-1)
    pr.add_argument("--ilpi", type=int, default=-1)
    pr.add_argument("--mlpi", type=int, default=-1)
    pr.add_argument("--minlen", type=int)
    pr.add_argument("--mode")
    pr.add_argument("--stats")
    pr.add_argument("--overhang", type=int)
    pr.add_argument("--extra-args", help="透传 orfanage 额外参数")
    pr.add_argument("--threads", type=int, help="覆盖默认线程数")
    pr.add_argument("--tmpdir", help="覆盖默认临时目录")
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = OrfanageSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OrfanageSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

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
