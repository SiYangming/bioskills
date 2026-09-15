#!/usr/bin/env python3
"""eggnog-mapper native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py annotate -i proteins.fasta -o eggNOG -m diamond --data_dir ~/db/emapperdb-4.5.1 --threads 8
   python main.py annotate_hits --annotate_hits_table hits.tsv -o eggNOG --data_dir ~/db/emapperdb-4.5.1
   python main.py download_db --data_dir ~/db
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（emapper.py，数据库 emapperdb-4.5.1 需单独下载）：
  annotate       emapper.py -i <fasta> -o <out> -m <method> --cpu N [--data_dir DIR] [...]
  annotate_hits  emapper.py --annotate_hits_table <hits> -o <out> --cpu N [--data_dir DIR]
  download_db    download_eggnog_data.py -y -f --data_dir DIR [-P <db>]
所有子命令自动注入线程（--cpu）与环境变量优化。
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
    "annotate": "蛋白 FASTA 功能注释（emapper.py -i <fasta> 同源搜索 + 注释）",
    "annotate_hits": "基于预计算命中表注释（emapper.py --annotate_hits_table）",
    "download_db": "下载 eggNOG 数据库（download_eggnog_data.py）",
}

# 子命令 -> 需要的可执行文件名（均来自 eggnog-mapper 发行包）
BINARY_FOR = {
    "annotate": "emapper.py",
    "annotate_hits": "emapper.py",
    "download_db": "download_eggnog_data.py",
}


class EggnogMapperSkill(base.SkillBase):
    software = "eggnog-mapper"
    binary = "emapper.py"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析对应可执行文件（惰性；测试可 monkeypatch）。

        name 省略或等于 self.binary 时走基类（self.binary）；否则解析传入的可执行名
        （download_db 需要 download_eggnog_data.py，而不是 emapper.py）。
        """
        target = name or self.binary
        if target == (self.binary or self.software):
            return super()._resolve_binary()
        path = base.which(target)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{target}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 eggnog-mapper 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(BINARY_FOR[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))
        data_dir = kw.get("data_dir")

        if subcommand == "download_db":
            cmd: list[str] = [binary]
            if data_dir:
                cmd += ["--data_dir", str(data_dir)]
            cmd += ["-y", "-f"]
            if kw.get("db"):
                cmd += ["-P", str(kw["db"])]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        cmd = [binary]
        if subcommand == "annotate":
            if not kw.get("input"):
                raise ValueError("annotate 缺少必填参数 input（-i 蛋白 FASTA）")
            cmd += ["-i", str(kw["input"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-m", str(kw.get("method") or "diamond")]
            cmd += ["--cpu", str(threads)]
            if data_dir:
                cmd += ["--data_dir", str(data_dir)]
            if kw.get("output_dir"):
                cmd += ["--output_dir", str(kw["output_dir"])]
            if kw.get("tax_scope"):
                cmd += ["--tax_scope", str(kw["tax_scope"])]
            if kw.get("target_orthologs"):
                cmd += ["--target_orthologs", str(kw["target_orthologs"])]
            if kw.get("go_evidence"):
                cmd += ["--go_evidence", str(kw["go_evidence"])]
            if kw.get("no_file_comments"):
                cmd.append("--no_file_comments")
            if kw.get("dbmem"):
                cmd.append("--dbmem")

        elif subcommand == "annotate_hits":
            if not kw.get("hits_table"):
                raise ValueError("annotate_hits 缺少必填参数 hits_table（--annotate_hits_table）")
            cmd += ["--annotate_hits_table", str(kw["hits_table"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["--cpu", str(threads)]
            if data_dir:
                cmd += ["--data_dir", str(data_dir)]
            if kw.get("output_dir"):
                cmd += ["--output_dir", str(kw["output_dir"])]
            if kw.get("no_file_comments"):
                cmd.append("--no_file_comments")

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
        prog="eggnog-mapper-skill",
        description="eggnog-mapper native 技能驱动（功能注释，自动线程/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # annotate
    pa = sub.add_parser("annotate", help=SUBCOMMANDS["annotate"])
    pa.add_argument("-i", "--input", required=True, help="输入蛋白 FASTA")
    pa.add_argument("-o", "--output", help="输出前缀（生成 <output>.emapper.annotations 等）")
    pa.add_argument("-m", "--method", help="同源搜索方法：diamond（默认）| hmmer | mmseqs")
    pa.add_argument("--data_dir", "--data-dir", dest="data_dir", help="eggNOG 数据库目录（emapperdb）")
    pa.add_argument("--output_dir", "--output-dir", dest="output_dir", help="输出目录（默认当前目录）")
    pa.add_argument("--tax_scope", "--tax-scope", dest="tax_scope", help="限定注释分类范围（如 Fungi/Bacteria/auto）")
    pa.add_argument("--target_orthologs", "--target-orthologs", dest="target_orthologs", help="目标同源类型（one2one|many2one|all）")
    pa.add_argument("--go_evidence", "--go-evidence", dest="go_evidence", help="GO 证据类型（experimental|non-electronic|all）")
    pa.add_argument("--no_file_comments", "--no-file-comments", dest="no_file_comments", action="store_true", help="输出不含 # 注释行")
    pa.add_argument("--dbmem", action="store_true", help="数据库载入内存（加速，需较大内存）")
    pa.add_argument("--extra-args", help="透传给 emapper.py 的额外参数")
    _add_runtime_opts(pa)

    # annotate_hits
    ph = sub.add_parser("annotate_hits", help=SUBCOMMANDS["annotate_hits"])
    ph.add_argument("--annotate_hits_table", "--annotate-hits-table", dest="hits_table", required=True, help="预计算同源命中表")
    ph.add_argument("-o", "--output", help="输出前缀")
    ph.add_argument("--data_dir", "--data-dir", dest="data_dir", help="eggNOG 数据库目录（emapperdb）")
    ph.add_argument("--output_dir", "--output-dir", dest="output_dir", help="输出目录")
    ph.add_argument("--no_file_comments", "--no-file-comments", dest="no_file_comments", action="store_true", help="输出不含 # 注释行")
    ph.add_argument("--extra-args", help="透传给 emapper.py 的额外参数")
    _add_runtime_opts(ph)

    # download_db
    pd = sub.add_parser("download_db", help=SUBCOMMANDS["download_db"])
    pd.add_argument("--data_dir", "--data-dir", dest="data_dir", required=True, help="数据库下载目标目录")
    pd.add_argument("-P", "--db", help="指定下载的数据库（默认全部，如 eggnog.db/eggnog_proteins.dmnd）")
    pd.add_argument("--extra-args", help="透传给 download_eggnog_data.py 的额外参数")
    _add_runtime_opts(pd)

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
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = EggnogMapperSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EggnogMapperSkill()
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
