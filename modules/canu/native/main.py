#!/usr/bin/env python3
"""canu native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble reads.fasta --prefix out --genome-size 58000 --data-type pacbio-raw --threads 8
   python main.py correct reads.fasta --prefix out --genome-size 8m --data-type nanopore-raw
   python main.py trim reads.fasta --prefix out --genome-size 8m
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（文档 04.md 第 1230/1245 行）：
  canu -p <prefix> [-d <dir>] genomeSize=<size> useGrid=false [maxThreads=N] -pacbio-raw <reads...>
  canu 的 -p 是输出前缀（不是线程数）；单机并发由 useGrid=false + maxThreads=N 控制。
  correct / trim 子命令分别追加 -correct / -trim 只跑对应阶段。
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus。
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
    "assemble": "完整组装 correct→trim→assemble（canu -p <prefix> genomeSize=<size> useGrid=false -pacbio-raw/-nanopore-raw）",
    "correct": "仅纠错阶段（追加 -correct）",
    "trim": "仅修剪阶段（追加 -trim）",
}

# 数据类型 -> canu 输入参数
DATA_TYPE_FLAGS = {
    "pacbio-raw": "-pacbio-raw",
    "pacbio-corrected": "-pacbio-corrected",
    "nanopore-raw": "-nanopore-raw",
    "nanopore-corrected": "-nanopore-corrected",
    "pacbio-hifi": "-pacbio-hifi",
}

# 阶段标志
STAGE_FLAGS = {"assemble": None, "correct": "-correct", "trim": "-trim"}


class CanuSkill(base.SkillBase):
    software = "canu"
    binary = "canu"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析 canu 二进制（可被测试 monkeypatch）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 canu 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        prefix = kw.get("prefix")
        if not prefix:
            raise ValueError("缺少必填参数 prefix（-p 输出前缀）")
        genome_size = kw.get("genome_size")
        if not genome_size:
            raise ValueError("缺少必填参数 genome_size（genomeSize=<n>[g|m|k]）")

        reads = kw.get("reads")
        if isinstance(reads, str):
            reads = [reads]
        if not reads:
            raise ValueError("缺少必填参数 reads（输入长读序列文件）")

        threads = self._effective_threads(subcommand, kw.get("threads"))
        data_type = str(kw.get("data_type") or "pacbio-raw")
        if data_type not in DATA_TYPE_FLAGS:
            raise ValueError(
                f"未知 data_type: {data_type}（可选 {sorted(DATA_TYPE_FLAGS)}）"
            )

        cmd: list[str] = [binary, "-p", str(prefix)]
        if kw.get("directory"):
            cmd += ["-d", str(kw["directory"])]

        cmd.append(f"genomeSize={genome_size}")
        cmd.append("useGrid=true" if kw.get("use_grid") else "useGrid=false")
        if not kw.get("use_grid"):
            cmd.append(f"maxThreads={threads}")

        stage = STAGE_FLAGS[subcommand]
        if stage:
            cmd.append(stage)

        cmd.append(DATA_TYPE_FLAGS[data_type])
        cmd += [str(r) for r in reads]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 maxThreads=）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("reads", nargs="+", help="输入长读序列文件（FASTA/FASTQ）")
    p.add_argument("-p", "--prefix", required=True, help="输出文件前缀（canu -p，非线程数）")
    p.add_argument("-d", "--directory", help="输出目录（默认 <prefix>）")
    p.add_argument("--genome-size", required=True, help="估计基因组大小（如 58000 / 8m）")
    p.add_argument("--data-type", default="pacbio-raw", choices=sorted(DATA_TYPE_FLAGS),
                   help="数据类型（默认 pacbio-raw）")
    p.add_argument("--use-grid", action="store_true", help="使用集群（默认单机 useGrid=false）")
    p.add_argument("--extra-args", help="透传给 canu 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="canu-skill",
        description="canu native 技能驱动（自动 maxThreads / useGrid=false 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    for name in ("assemble", "correct", "trim"):
        sp = sub.add_parser(name, help=SUBCOMMANDS[name])
        _add_common(sp)
        _add_runtime_opts(sp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = CanuSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CanuSkill()
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
