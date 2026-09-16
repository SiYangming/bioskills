#!/usr/bin/env python3
"""masurca native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py config config.txt                          # 生成 assemble.sh
   python main.py simple --pe illumina.1.fastq,illumina.2.fastq --long-reads subreads.fasta -t 32
   python main.py run --script assemble.sh --log masurca.log # 执行组装
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  config   masurca <config.txt>                 # 生成 assemble.sh
  simple   masurca -t <N> -i <R1,R2> [-r <long>] # 简化模式直跑全流程
  run      bash <assemble.sh>                   # 执行生成的组装脚本（日志重定向由 shell 完成）
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus（simple 注入 -t；
config/run 由 config.txt 的 NUM_THREADS 或 assemble.sh 自身控制）。
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
    "config": "由 config.txt 生成组装驱动脚本 assemble.sh（masurca <config.txt>）",
    "simple": "简化模式直跑全流程（masurca -t N -i R1,R2 [-r long.fa]）",
    "run": "执行生成的组装脚本（bash assemble.sh，日志重定向由 shell 完成）",
}

# 使用工具二进制的子命令（run 走 bash 执行脚本，不需要 masurca 二进制）
NEEDS_BINARY = {"config", "simple"}


class MasurcaSkill(base.SkillBase):
    software = "masurca"
    binary = "masurca"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析 masurca 二进制（可被测试 monkeypatch）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer/源码编译安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 masurca / assemble.sh 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "config":
            binary = self._resolve_binary()
            config = kw.get("config") or kw.get("input")
            if not config:
                raise ValueError("config 缺少必填参数 config（config.txt 路径）")
            cmd: list[str] = [binary, str(config)]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        if subcommand == "simple":
            binary = self._resolve_binary()
            pe = kw.get("pe_reads")
            if not pe:
                raise ValueError("simple 缺少必填参数 pe_reads（-i R1,R2 逗号分隔）")
            cmd = [binary, "-t", str(threads), "-i", str(pe)]
            if kw.get("long_reads"):
                cmd += ["-r", str(kw["long_reads"])]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        # run：执行生成的 assemble.sh（bash <script>）
        script = kw.get("script") or "assemble.sh"
        return ["bash", str(script)]

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（simple 注入 -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="masurca-skill",
        description="MaSuRCA native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # config
    pc = sub.add_parser("config", help=SUBCOMMANDS["config"])
    pc.add_argument("config", nargs="?", help="config.txt 路径（别名 --config）")
    pc.add_argument("--config", dest="config_alias", help="config.txt 别名")
    pc.add_argument("--extra-args", help="透传给 masurca 的额外参数")
    _add_runtime_opts(pc)

    # simple
    ps = sub.add_parser("simple", help=SUBCOMMANDS["simple"])
    ps.add_argument("-i", "--pe-reads", dest="pe_reads", required=True,
                    help="Illumina paired-end reads，逗号分隔的 R1,R2")
    ps.add_argument("-r", "--long-reads", dest="long_reads", help="长读文件（可选）")
    ps.add_argument("--extra-args", help="透传给 masurca 的额外参数")
    _add_runtime_opts(ps)

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("--script", default="assemble.sh", help="待执行的组装脚本（默认 assemble.sh）")
    pr.add_argument("--log", help="组装日志文件（默认 masurca.log，重定向 stdout+stderr）")
    _add_runtime_opts(pr)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = MasurcaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MasurcaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    # positional config 与 --config 别名合并为 config
    if "config_alias" in kw:
        kw.setdefault("config", kw.pop("config_alias"))
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # run 子命令：stdout 落到 --log（若指定）
    if ns.subcommand == "run" and getattr(ns, "log", None):
        with open(ns.log, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
            if result.stderr:
                fh.write(result.stderr)
        return result.returncode

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
