#!/usr/bin/env python3
"""blast（NCBI BLAST+）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py makeblastdb refs.fa --dbtype nucl --out refs_db --threads 4
   python main.py blastn -query query.fa -db refs_db -o hits.tsv --outfmt 6 --evalue 1e-5 --threads 4
   python main.py blastp -query prot.fa -db prot_db -o hits.tsv --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（--threads -> -num_threads）与临时目录（--tmpdir）。

三个子命令分别包装 NCBI BLAST+ 的对应程序：
- makeblastdb  建核苷酸/蛋白 BLAST 库（-in/-dbtype/-out）
- blastn       核苷酸 vs 核苷酸 局部比对搜索（-query/-db/-out/-outfmt/-evalue）
- blastp       蛋白 vs 蛋白 局部比对搜索（-query/-db/-out/-outfmt/-evalue）
"""
from __future__ import annotations

import argparse
import json
import shutil
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
    "makeblastdb": "makeblastdb：为核苷酸/蛋白 FASTA 建立 BLAST 库（-dbtype nucl|prot，产物 <prefix>.n*/.p* 索引族）",
    "blastn": "blastn：核苷酸 query 比对到核苷酸库（-query/-db，默认 -outfmt 6 表格）",
    "blastp": "blastp：蛋白 query 比对到蛋白库（-query/-db，默认 -outfmt 6 表格）",
}

# 子命令 -> BLAST+ 二进制
_BINARY_BY_SUBCOMMAND = {
    "makeblastdb": "makeblastdb",
    "blastn": "blastn",
    "blastp": "blastp",
}

_DB_TYPES = ("nucl", "prot")


class BlastSkill(base.SkillBase):
    software = "blast"
    binary = "blastn"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/blast/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析子命令对应的 BLAST+ 可执行文件，带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda blast（alias ncbi-blast+）会提供 blastn/blastp/makeblastdb 等全套二进制）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 BLAST+ 命令行。"""
        threads = self._effective_threads(subcommand, kw.get("threads"))
        tool = _BINARY_BY_SUBCOMMAND.get(subcommand)
        if tool is None:
            raise RuntimeError(f"未知子命令: {subcommand}")
        binary = self._resolve_tool(tool)

        if subcommand == "makeblastdb":
            input_fa = kw.get("input") or kw.get("input_opt")
            if not input_fa:
                raise RuntimeError("makeblastdb 需要 input（输入 FASTA，位置参数或 --input）")
            dbtype = str(kw.get("dbtype") or "nucl").lower()
            if dbtype not in _DB_TYPES:
                raise RuntimeError(f"makeblastdb 的 dbtype 只能是 {'|'.join(_DB_TYPES)}，收到: {dbtype}")
            db_prefix = kw.get("db_prefix") or kw.get("output")
            if not db_prefix:
                raise RuntimeError("makeblastdb 需要 -out/db_prefix（输出 BLAST 库前缀）")
            # 注：makeblastdb 无 -num_threads（单线程建库），--threads 仅作为运行期选项被接受，
            #     不注入命令行；线程注入只对 blastn/blastp 生效。
            cmd: list[str] = [
                binary,
                "-in", str(input_fa),
                "-dbtype", dbtype,
                "-out", str(db_prefix),
            ]
        elif subcommand in ("blastn", "blastp"):
            query = kw.get("query")
            if not query:
                raise RuntimeError(f"{subcommand} 需要 -query（查询序列 FASTA）")
            db = kw.get("db")
            if not db:
                raise RuntimeError(f"{subcommand} 需要 -db（BLAST 库前缀）")
            outfmt = kw.get("outfmt")
            cmd = [
                binary,
                "-query", str(query),
                "-db", str(db),
                "-outfmt", str(outfmt if outfmt is not None else "6"),
                "-num_threads", str(threads),
            ]
            evalue = kw.get("evalue")
            if evalue is not None:
                cmd += ["-evalue", str(evalue)]
            output = kw.get("output")
            if output:
                cmd += ["-out", str(output)]
        else:  # pragma: no cover - 上游已拦截
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="blast-skill",
        description="blast（NCBI BLAST+）native 技能驱动（自动线程/TMPDIR；建库 + blastn/blastp 比对搜索）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # makeblastdb: makeblastdb -in <fasta> -dbtype <nucl|prot> -out <prefix>
    pm = sub.add_parser("makeblastdb", help=SUBCOMMANDS["makeblastdb"])
    pm.add_argument("input", nargs="?", help="输入 FASTA（建库对象；也可用 --input 指定）")
    pm.add_argument("--input", dest="input_opt", help="输入 FASTA（与位置参数等价）")
    pm.add_argument("--dbtype", default="nucl", choices=list(_DB_TYPES),
                    help="库类型：nucl（默认，供 blastn）| prot（供 blastp）")
    pm.add_argument("--out", dest="db_prefix", help="输出 BLAST 库前缀（-out basename）")
    pm.add_argument("--extra-args", dest="extra_args", help="透传给 makeblastdb 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pm)

    # blastn / blastp: <prog> -query <q> -db <db> [-out <o>] [-outfmt 6] [-evalue E]
    for name in ("blastn", "blastp"):
        pt = sub.add_parser(name, help=SUBCOMMANDS[name])
        pt.add_argument("-query", "--query", required=True, help="查询序列 FASTA")
        pt.add_argument("-db", "--db", required=True, help="BLAST 库前缀（makeblastdb 的 -out 值）")
        pt.add_argument("-out", "-o", "--output", dest="output", help="结果输出文件（缺省 stdout）")
        pt.add_argument("--outfmt", default="6", help="结果格式（默认 6 表格；可写 \"6 qseqid sseqid pident evalue bitscore\"）")
        pt.add_argument("--evalue", type=float, help="期望值阈值（E-value）")
        pt.add_argument("--extra-args", dest="extra_args", help="透传给 %s 的额外参数（高级用法，慎用）" % name)
        _add_runtime_opts(pt)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -num_threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = BlastSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BlastSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

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
