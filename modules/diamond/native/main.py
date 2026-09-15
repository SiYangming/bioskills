#!/usr/bin/env python3
"""diamond native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py makedb --db uniprot_sprot --in uniprot_sprot.fasta --threads 8
   python main.py blastp --db uniprot_sprot --query longest_orfs.pep --out blast.xml \
       --outfmt 5 --sensitive --evalue 1e-5 --max-target-seqs 20 --threads 8
   python main.py blastx --db nr --query transcripts.fa --out blastx.tsv --outfmt 6 --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  makedb   diamond makedb --threads N --db <db> --in <protein.fasta>
  blastp   diamond blastp --db <db> --query <q> --out <out> [--outfmt N] --threads N --tmpdir <T>
  blastx   diamond blastx --db <db> --query <q> --out <out> [--outfmt N] --threads N --tmpdir <T>
所有子命令自动注入线程与临时目录优化。
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
    "makedb": "为蛋白 FASTA 构建 DIAMOND 比对数据库",
    "blastp": "蛋白序列 vs 蛋白库比对（blastp）",
    "blastx": "核酸序列 vs 蛋白库比对（blastx）",
}

# 需要 --tmpdir / 比对参数搜索的子命令
SEARCH_SUBCOMMANDS = {"blastp", "blastx"}


class DiamondSkill(base.SkillBase):
    software = "diamond"
    binary = "diamond"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 DIAMOND 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "makedb":
            db = kw.get("db")
            if not db:
                raise ValueError("makedb 缺少必填参数 db（--db 输出数据库前缀）")
            inp = kw.get("input") or kw.get("in")
            if not inp:
                raise ValueError("makedb 缺少必填参数 input（--in 蛋白 FASTA）")
            cmd: list[str] = [
                binary, "makedb",
                "--threads", str(threads),
                "--db", str(db),
                "--in", str(inp),
            ]

        else:  # blastp / blastx
            db = kw.get("db")
            if not db:
                raise ValueError(f"{subcommand} 缺少必填参数 db（--db）")
            query = kw.get("query")
            if not query:
                raise ValueError(f"{subcommand} 缺少必填参数 query（--query）")
            out = kw.get("output") or kw.get("out")
            if not out:
                raise ValueError(f"{subcommand} 缺少必填参数 output（--out）")
            cmd = [
                binary, subcommand,
                "--db", str(db),
                "--query", str(query),
                "--out", str(out),
                "--threads", str(threads),
                "--tmpdir", str(self.tmpdir),
            ]
            if kw.get("outfmt") is not None:
                cmd += ["--outfmt", str(kw["outfmt"])]
            if kw.get("sensitive"):
                cmd.append("--sensitive")
            if kw.get("max_target_seqs") is not None:
                cmd += ["--max-target-seqs", str(kw["max_target_seqs"])]
            if kw.get("evalue") is not None:
                cmd += ["--evalue", str(kw["evalue"])]
            if kw.get("min_id") is not None:
                cmd += ["--id", str(kw["min_id"])]
            if kw.get("index_chunks") is not None:
                cmd += ["--index-chunks", str(kw["index_chunks"])]

        # 高级透传（慎用）
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
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="diamond-skill",
        description="diamond native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # makedb
    pm = sub.add_parser("makedb", help=SUBCOMMANDS["makedb"])
    pm.add_argument("--db", required=True, help="输出数据库前缀（--db）")
    pm.add_argument("--in", dest="input", required=True, help="输入蛋白 FASTA（--in）")
    pm.add_argument("--extra-args", help="透传给 diamond 的额外参数")
    _add_runtime_opts(pm)

    # blastp / blastx
    for name in ("blastp", "blastx"):
        pb = sub.add_parser(name, help=SUBCOMMANDS[name])
        pb.add_argument("--db", required=True, help="DIAMOND 数据库（--db）")
        pb.add_argument("--query", required=True, help="查询序列（--query）")
        pb.add_argument("-o", "--output", required=True, help="比对结果输出文件（--out）")
        pb.add_argument("--outfmt", type=int, help="输出格式（5=XML，6=tabular；diamond 默认 6）")
        pb.add_argument("--sensitive", action="store_true", help="开启 --sensitive（更灵敏、更慢）")
        pb.add_argument("--max-target-seqs", type=int, help="每条 query 最大命中数（--max-target-seqs）")
        pb.add_argument("--evalue", type=float, help="E-value 阈值（--evalue）")
        pb.add_argument("--min-id", type=float, help="最小一致性百分比（--id）")
        pb.add_argument("--index-chunks", type=int, help="索引分块数（--index-chunks）")
        pb.add_argument("--extra-args", help="透传给 diamond 的额外参数")
        _add_runtime_opts(pb)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = DiamondSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = DiamondSkill()
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
