#!/usr/bin/env python3
"""interproscan native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -i proteins.fasta -o interpro_result -f tsv,gff3,xml --goterms --iprlookup --pa --threads 8
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（interproscan.sh，依赖 Java，数据在官方发行包 data/ 下）：
  run      interproscan.sh -i <fasta> -o <out> -f <formats> [-goterms] [-iprlookup] [-pa] [-dp] [-appl X] -cpu N [--tempdir DIR]
  version  interproscan.sh --version
所有子命令自动注入线程（-cpu）、临时目录（--tempdir）与 JAVA_OPTS（-Xmx / -Djava.io.tmpdir）。
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
    "run": "蛋白功能域注释（interproscan.sh -i <fasta> -f ... -cpu N）",
    "version": "打印 InterProScan 版本（interproscan.sh --version）",
}


class InterproscanSkill(base.SkillBase):
    software = "interproscan"
    binary = "interproscan.sh"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 interproscan 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        if subcommand == "version":
            return [binary, "--version"]

        if not kw.get("input"):
            raise ValueError("run 缺少必填参数 input（-i 蛋白序列 FASTA）")
        threads = self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = [binary, "-i", str(kw["input"])]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        if kw.get("formats"):
            cmd += ["-f", str(kw["formats"])]
        # 布尔开关：默认 goterms/iprlookup 开启
        if kw.get("goterms", True):
            cmd.append("-goterms")
        if kw.get("iprlookup", True):
            cmd.append("-iprlookup")
        if kw.get("pathways"):
            cmd.append("-pa")
        if kw.get("disable_precalc"):
            cmd.append("-dp")
        if kw.get("appl"):
            cmd += ["-appl", str(kw["appl"])]
        if kw.get("seqtype"):
            cmd += ["-t", str(kw["seqtype"])]
        cmd += ["-cpu", str(threads)]
        tmpdir = kw.get("tmpdir_override") or self.tmpdir
        if tmpdir:
            cmd += ["--tempdir", str(tmpdir)]

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
        prog="interproscan-skill",
        description="interproscan native 技能驱动（蛋白功能域注释，自动线程/Java 内存优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-i", "--input", required=True, help="输入蛋白序列 FASTA")
    pr.add_argument("-o", "--output", help="输出文件路径")
    pr.add_argument("-f", "--formats", help="输出格式（逗号分隔，如 tsv,gff3,xml）")
    pr.add_argument("--no-goterms", dest="goterms", action="store_false", help="关闭 GO 注释输出（-goterms）")
    pr.add_argument("--no-iprlookup", dest="iprlookup", action="store_false", help="关闭 InterPro 条目查询（-iprlookup）")
    pr.add_argument("-pa", "--pathways", action="store_true", help="输出通路注释（-pa）")
    pr.add_argument("-dp", "--disable-precalc", dest="disable_precalc", action="store_true", help="关闭 precalculated 匹配（-dp）")
    pr.add_argument("-appl", "--appl", help="限定分析应用（逗号分隔，如 pfam,prints,smart）")
    pr.add_argument("-t", "--seqtype", help="序列类型：p（蛋白，默认）| n（核酸）")
    pr.add_argument("--extra-args", help="透传给 interproscan.sh 的额外参数")
    _add_runtime_opts(pr)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（映射为 --tempdir）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = InterproscanSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = InterproscanSkill()
    tmp_override = getattr(ns, "tmpdir", None)
    if tmp_override:
        skill.tmpdir = tmp_override

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads
    kw["tmpdir_override"] = tmp_override

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
