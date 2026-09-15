#!/usr/bin/env python3
"""metaeuk native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py easy_predict contigs.fna proteins.faa preds temp --threads 8
   python main.py easy_search query.faa target.faa hits.m8 tmp --threads 8
   python main.py taxtocontig contigsDB preds.fas headersMap.tsv seqTaxDb taxResult tmp --majority 0.5
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（MetaEuk 2-ddf2742，MMseqs2 风格 CLI）：
  easy_predict   metaeuk easy-predict <contigs> <targets> <out_prefix> <tmp_dir> --threads N
  easy_search    metaeuk easy-search <query> <target> <out_file> <tmp_dir> --threads N
  taxtocontig    metaeuk taxtocontig <contigsDB> <preds.fas> <headersMap.tsv> <taxDb> <out> <tmpDir> ...
  version        metaeuk version
二进制经 PATH 惰性解析（测试时 monkeypatch）；临时目录缺省取 self.tmpdir。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "easy_predict": "contigs + 参考蛋白 -> 预测蛋白 FASTA + GFF（metaeuk easy-predict 端到端）",
    "easy_search": "query + target -> 同源搜索结果（metaeuk easy-search）",
    "taxtocontig": "预测结果 + 分类蛋白库 -> 按 contig 的分类注释（metaeuk taxtocontig）",
    "version": "打印 metaeuk 版本（metaeuk version）",
}


class MetaeukSkill(base.SkillBase):
    software = "metaeuk"
    binary = "metaeuk"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 metaeuk 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        tmp = kw.get("tmp_dir") or self.tmpdir

        if subcommand == "version":
            return [binary, "version"]

        if subcommand == "easy_predict":
            contigs, targets = kw.get("contigs"), kw.get("targets")
            out_prefix = kw.get("out_prefix")
            if not contigs or not targets or not out_prefix:
                raise ValueError("easy_predict 需要 contigs / targets / out_prefix 三个位置参数")
            cmd = [binary, "easy-predict", str(contigs), str(targets), str(out_prefix), str(tmp)]

        elif subcommand == "easy_search":
            query, target, out_file = kw.get("query"), kw.get("target"), kw.get("out_file")
            if not query or not target or not out_file:
                raise ValueError("easy_search 需要 query / target / out_file 三个位置参数")
            cmd = [binary, "easy-search", str(query), str(target), str(out_file), str(tmp)]

        elif subcommand == "taxtocontig":
            contigs_db = kw.get("contigs_db")
            preds_fas = kw.get("preds_fas")
            headers_map = kw.get("headers_map")
            tax_db = kw.get("tax_target_db")
            out_file = kw.get("out_file")
            if not all((contigs_db, preds_fas, headers_map, tax_db, out_file)):
                raise ValueError(
                    "taxtocontig 需要 contigs_db / preds_fas / headers_map / tax_target_db / out_file 位置参数"
                )
            cmd = [binary, "taxtocontig", str(contigs_db), str(preds_fas), str(headers_map),
                   str(tax_db), str(out_file), str(tmp)]
            if kw.get("majority") is not None:
                cmd += ["--majority", str(kw["majority"])]
            if kw.get("tax_lineage") is not None:
                cmd += ["--tax-lineage", str(kw["tax_lineage"])]
            if kw.get("lca_mode") is not None:
                cmd += ["--lca-mode", str(kw["lca_mode"])]

        cmd += ["--threads", str(self._effective_threads(subcommand, kw.get("threads")))]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="metaeuk-skill",
        description="metaeuk native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # easy_predict
    pe = sub.add_parser("easy_predict", help=SUBCOMMANDS["easy_predict"])
    pe.add_argument("contigs", help="目标 contig FASTA 或已建库")
    pe.add_argument("targets", help="参考蛋白 FASTA / 蛋白库 / 谱库")
    pe.add_argument("out_prefix", help="结果前缀（<prefix>.fas/.gff）")
    pe.add_argument("tmp_dir", nargs="?", help="临时目录（默认取 --tmpdir）")
    pe.add_argument("--extra-args", help="透传给 metaeuk 的额外参数")
    _add_runtime_opts(pe)

    # easy_search
    ps = sub.add_parser("easy_search", help=SUBCOMMANDS["easy_search"])
    ps.add_argument("query", help="查询序列")
    ps.add_argument("target", help="目标序列/库")
    ps.add_argument("out_file", help="结果输出路径")
    ps.add_argument("tmp_dir", nargs="?", help="临时目录（默认取 --tmpdir）")
    ps.add_argument("--extra-args", help="透传给 metaeuk 的额外参数")
    _add_runtime_opts(ps)

    # taxtocontig
    pt = sub.add_parser("taxtocontig", help=SUBCOMMANDS["taxtocontig"])
    pt.add_argument("contigs_db", help="已建 contig 库")
    pt.add_argument("preds_fas", help="MetaEuk 预测蛋白 FASTA")
    pt.add_argument("headers_map", help="预测到内部标识的 TSV 映射")
    pt.add_argument("tax_target_db", help="带分类信息的蛋白库")
    pt.add_argument("out_file", help="分类结果输出路径")
    pt.add_argument("tmp_dir", nargs="?", help="临时目录（默认取 --tmpdir）")
    pt.add_argument("--majority", type=float, help="多数投票阈值（如 0.5）")
    pt.add_argument("--tax-lineage", dest="tax_lineage", type=int, help="是否输出分类谱系（0/1）")
    pt.add_argument("--lca-mode", dest="lca_mode", type=int, help="LCA 模式")
    pt.add_argument("--extra-args", help="透传给 metaeuk 的额外参数")
    _add_runtime_opts(pt)

    # version
    sub.add_parser("version", help=SUBCOMMANDS["version"])

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = MetaeukSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MetaeukSkill()
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
