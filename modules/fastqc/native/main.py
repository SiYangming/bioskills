#!/usr/bin/env python3
"""fastqc native 标准入口驱动。

两种模式：
  python main.py run READS [READS ...] [-o OUTDIR] [--threads N] [--java-mem-mb M]
  python main.py --schema | --list-commands
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402


class FastqcSkill(base.SkillBase):
    software = "fastqc"
    binary = "fastqc"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        binary = self._resolve_binary()
        cmd = [binary]

        # FastQC 是单命令程序；子命令固定为 "run"
        reads = kw.get("reads") or []
        if not reads:
            raise RuntimeError("FastQC 至少需要一个 reads 文件")

        # outdir（默认 ./fastqc_results，若不存在则创建）
        outdir = kw.get("outdir") or "fastqc_results"
        Path(outdir).mkdir(parents=True, exist_ok=True)
        cmd += ["-o", str(outdir)]

        # 线程
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-t", str(threads)]

        # 解压开关
        if kw.get("extract") and not kw.get("noextract"):
            cmd.append("--extract")
        if kw.get("noextract"):
            cmd.append("--noextract")

        if kw.get("nogroup"):
            cmd.append("--nogroup")

        if kw.get("format"):
            cmd += ["-f", str(kw["format"])]
        if kw.get("contaminants"):
            cmd += ["-c", str(kw["contaminants"])]
        if kw.get("adapters"):
            cmd += ["-a", str(kw["adapters"])]
        if kw.get("kmers"):
            cmd += ["-k", str(kw["kmers"])]

        # JVM 内存通过 env_vars 注入（meta.yaml 用 {mem_mb} 占位符）
        # 但用户如果通过 --java-mem-mb 显式覆盖，需要再更新 env_vars
        java_mem = kw.get("java_mem_mb")
        if java_mem and self.mem_mb != int(java_mem):
            self.mem_mb = int(java_mem)
            # 重建 JAVA_OPTS
            self.env_vars.update(self._render_env_vars(
                self.meta.get("optimization", {}).get("env_vars", {})
            ))

        # reads 位置参数放最后
        if isinstance(reads, (list, tuple)):
            cmd += [str(r) for r in reads]
        else:
            cmd.append(str(reads))
        return cmd


SUBCOMMANDS = {"run": "FastQC 质控主流程"}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fastqc-skill",
        description="fastqc native 技能驱动（JVM 内存 + 线程 + 临时目录自动优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema")
    p.add_argument("--list-commands", action="store_true", help="列出子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("reads", nargs="+", help="一个或多个 FASTQ/FASTQ.gz 文件")
    pr.add_argument("-o", "--outdir", default="fastqc_results")
    pr.add_argument("--threads", type=int)
    pr.add_argument("--tmpdir")
    pr.add_argument("--java-mem-mb", type=int, dest="java_mem_mb", default=8192)
    pr.add_argument("--extract", action="store_true", default=True)
    pr.add_argument("--noextract", action="store_true")
    pr.add_argument("--nogroup", action="store_true")
    pr.add_argument("-f", "--format")
    pr.add_argument("-c", "--contaminants")
    pr.add_argument("-a", "--adapters")
    pr.add_argument("-k", "--kmers", type=int)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = FastqcSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FastqcSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items() if k not in ("subcommand", "tmpdir") and v is not None}
    # argparse nargs+ 会把位置参数写成 list，正好给 FastQC 多文件能力

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
