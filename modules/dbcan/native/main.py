#!/usr/bin/env python3
"""dbcan native 标准入口驱动（dbCAN V9 经典「数据库 + 脚本」路线）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py build_hmm --hmm_db dbCAN-fam-HMMs.txt
   python main.py build_blastdb --fasta CAZyDB.07312020.fa --blast_db CAZyDB.07312020 --title CAZyDB.07312020
   python main.py build_diamond --fasta CAZyDB.07312020.fa --db CAZyDB.07312020
   python main.py hmmscan --hmm_db dbCAN-fam-HMMs.txt --fasta proteins.fasta \
       --domtblout hmmscan.domtbl --evalue 1e-3 --dom_evalue 1e-3 --threads 8
   python main.py diamond_blastp --db CAZyDB.07312020 --fasta proteins.fasta \
       --output diamond.xml --outfmt 5 --sensitive --evalue 1e-5 --max_target_seqs 500 --threads 8
   python main.py parse_hmmscan --domtblout hmmscan.domtbl -o hmmscan.out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（dbCAN V9：hmmpress / makeblastdb / diamond / hmmscan / hmmscan-parser.sh）：
  build_hmm       hmmpress <hmm_db>
  build_blastdb   makeblastdb -in <fasta> -dbtype prot -title <t> -parse_seqids -out <db> -logfile <log>
  build_diamond   diamond makedb --in <fasta> --db <db>
  hmmscan         hmmscan --cpu N -E <e> --domE <de> --domtblout <out> <hmm_db> <fasta>
  diamond_blastp  diamond blastp --db <db> --query <fasta> --out <out> --outfmt <n> ... --threads N
  parse_hmmscan   hmmscan-parser.sh <domtblout>（结果写 stdout，-o 落盘）
所有子命令自动注入线程与环境变量优化。
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
    "build_hmm": "用 hmmpress 建立 dbCAN HMM 数据库（.h3f/.h3i/.h3m/.h3p）",
    "build_blastdb": "用 makeblastdb 建立 CAZy 蛋白 BLAST 库",
    "build_diamond": "用 diamond makedb 建立 CAZy DIAMOND 库",
    "hmmscan": "用 hmmscan 对蛋白序列扫描 dbCAN HMM 库（域级 domtblout）",
    "diamond_blastp": "用 diamond blastp 对蛋白序列比对 CAZy 库",
    "parse_hmmscan": "用 hmmscan-parser.sh 解析 hmmscan domtblout（CAZy 家族注释）",
}

# 子命令 -> 需要的可执行文件名（dbCAN V9 依赖的底层工具 + 自带脚本）
BINARY_FOR = {
    "build_hmm": "hmmpress",
    "build_blastdb": "makeblastdb",
    "build_diamond": "diamond",
    "hmmscan": "hmmscan",
    "diamond_blastp": "diamond",
    "parse_hmmscan": "hmmscan-parser.sh",
}


class DbcanSkill(base.SkillBase):
    software = "dbcan"
    binary = "hmmscan-parser.sh"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析对应可执行文件（惰性；测试可 monkeypatch）。"""
        target = name or self.binary
        if target == (self.binary or self.software):
            return super()._resolve_binary()
        path = base.which(target)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{target}'，请先安装（HMMER / BLAST+ / DIAMOND / dbCAN 脚本）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 dbCAN 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(BINARY_FOR[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "build_hmm":
            hmm = kw.get("hmm_db")
            if not hmm:
                raise ValueError("build_hmm 缺少必填参数 hmm_db（dbCAN-fam-HMMs.txt）")
            cmd = [binary, str(hmm)]

        elif subcommand == "build_blastdb":
            fasta, out = kw.get("fasta"), kw.get("blast_db")
            if not fasta or not out:
                raise ValueError("build_blastdb 缺少必填参数 fasta / blast_db")
            cmd = [binary, "-in", str(fasta), "-dbtype", "prot"]
            title = kw.get("title") or Path(str(fasta)).stem
            cmd += ["-title", str(title), "-parse_seqids", "-out", str(out)]
            cmd += ["-logfile", str(kw.get("logfile") or f"{out}.makeblastdb.log")]

        elif subcommand == "build_diamond":
            fasta, db = kw.get("fasta"), kw.get("db")
            if not fasta or not db:
                raise ValueError("build_diamond 缺少必填参数 fasta / db")
            cmd = [binary, "makedb", "--in", str(fasta), "--db", str(db)]

        elif subcommand == "hmmscan":
            hmm, fasta, domtbl = kw.get("hmm_db"), kw.get("fasta"), kw.get("domtblout")
            if not hmm or not fasta:
                raise ValueError("hmmscan 缺少必填参数 hmm_db / fasta")
            cmd = [binary, "--cpu", str(threads)]
            if kw.get("evalue") is not None:
                cmd += ["-E", str(kw["evalue"])]
            if kw.get("dom_evalue") is not None:
                cmd += ["--domE", str(kw["dom_evalue"])]
            if domtbl:
                cmd += ["--domtblout", str(domtbl)]
            cmd += [str(hmm), str(fasta)]

        elif subcommand == "diamond_blastp":
            db, fasta = kw.get("db"), kw.get("fasta")
            if not db or not fasta:
                raise ValueError("diamond_blastp 缺少必填参数 db / fasta")
            cmd = [binary, "blastp", "--db", str(db), "--query", str(fasta)]
            if kw.get("output"):
                cmd += ["--out", str(kw["output"])]
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
            cmd += ["--threads", str(threads)]
            if self.tmpdir:
                cmd += ["--tmpdir", str(self.tmpdir)]

        elif subcommand == "parse_hmmscan":
            domtbl = kw.get("domtblout")
            if not domtbl:
                raise ValueError("parse_hmmscan 缺少必填参数 domtblout（hmmscan 域级输出）")
            cmd = [binary, str(domtbl)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 交由 main() 输出）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dbcan-skill",
        description="dbcan native 技能驱动（CAZy 注释：建库 + hmmscan/diamond + 解析）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # build_hmm
    ph = sub.add_parser("build_hmm", help=SUBCOMMANDS["build_hmm"])
    ph.add_argument("--hmm_db", "--hmm-db", dest="hmm_db", required=True, help="dbCAN HMM 数据库文件")
    ph.add_argument("--extra-args", help="透传给 hmmpress 的额外参数")
    _add_runtime_opts(ph)

    # build_blastdb
    pb = sub.add_parser("build_blastdb", help=SUBCOMMANDS["build_blastdb"])
    pb.add_argument("--fasta", required=True, help="CAZy 蛋白 FASTA（CAZyDB.07312020.fa）")
    pb.add_argument("--blast_db", "--blast-db", dest="blast_db", required=True, help="BLAST 库输出前缀")
    pb.add_argument("--title", help="BLAST 库标题（默认取 FASTA 文件名）")
    pb.add_argument("--logfile", help="makeblastdb 日志文件")
    pb.add_argument("--extra-args", help="透传给 makeblastdb 的额外参数")
    _add_runtime_opts(pb)

    # build_diamond
    pd = sub.add_parser("build_diamond", help=SUBCOMMANDS["build_diamond"])
    pd.add_argument("--fasta", required=True, help="CAZy 蛋白 FASTA（CAZyDB.07312020.fa）")
    pd.add_argument("--db", required=True, help="DIAMOND 库输出前缀")
    pd.add_argument("--extra-args", help="透传给 diamond makedb 的额外参数")
    _add_runtime_opts(pd)

    # hmmscan
    pm = sub.add_parser("hmmscan", help=SUBCOMMANDS["hmmscan"])
    pm.add_argument("--hmm_db", "--hmm-db", dest="hmm_db", required=True, help="dbCAN HMM 数据库文件")
    pm.add_argument("--fasta", required=True, help="输入蛋白 FASTA")
    pm.add_argument("--domtblout", required=True, help="域级输出文件")
    pm.add_argument("-E", "--evalue", type=float, help="E-value 阈值（默认 1e-3 见 13.md）")
    pm.add_argument("--dom_evalue", "--dom-evalue", dest="dom_evalue", type=float, help="域级 E-value 阈值")
    pm.add_argument("--extra-args", help="透传给 hmmscan 的额外参数")
    _add_runtime_opts(pm)

    # diamond_blastp
    pdb = sub.add_parser("diamond_blastp", help=SUBCOMMANDS["diamond_blastp"])
    pdb.add_argument("--db", required=True, help="DIAMOND 库前缀")
    pdb.add_argument("--fasta", required=True, help="输入蛋白 FASTA")
    pdb.add_argument("-o", "--output", help="比对结果输出文件")
    pdb.add_argument("--outfmt", type=int, help="输出格式（5=XML，6=tabular）")
    pdb.add_argument("--sensitive", action="store_true", help="开启 --sensitive 灵敏模式")
    pdb.add_argument("--max_target_seqs", "--max-target-seqs", dest="max_target_seqs", type=int, help="每条 query 最大命中数")
    pdb.add_argument("--evalue", type=float, help="E-value 阈值")
    pdb.add_argument("--min_id", "--min-id", dest="min_id", type=float, help="最小一致性百分比")
    pdb.add_argument("--index_chunks", "--index-chunks", dest="index_chunks", type=int, help="索引分块数")
    pdb.add_argument("--extra-args", help="透传给 diamond blastp 的额外参数")
    _add_runtime_opts(pdb)

    # parse_hmmscan
    pp = sub.add_parser("parse_hmmscan", help=SUBCOMMANDS["parse_hmmscan"])
    pp.add_argument("--domtblout", required=True, help="hmmscan 域级输出文件")
    pp.add_argument("-o", "--output", help="解析结果输出文件（默认 stdout）")
    pp.add_argument("--extra-args", help="透传给 hmmscan-parser.sh 的额外参数")
    _add_runtime_opts(pp)

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
            print(f"{k:15s} {v}")
        return 0
    if "--schema" in args:
        skill = DbcanSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = DbcanSkill()
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

    # parse_hmmscan 的 stdout 落到 output 文件（hmmscan-parser.sh 写 stdout）
    if ns.subcommand == "parse_hmmscan" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
