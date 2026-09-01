#!/usr/bin/env python3
"""sra-tools native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py prefetch SRR12345678 -O sra/ --threads 2
   python main.py fasterq-dump sra/SRR12345678/SRR12345678.sra -O fastq/ --split-3 --threads 8
   python main.py fastq-dump sra/SRR12345678/SRR12345678.sra --split-3 --gzip -O fastq/
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/nanoseq.smk/nanoseq.sh：
  batch_prefetch.sh:            prefetch -f yes -t http <srr_id>
  batch_sra_to_fastq.sh / parallel:  fastq-dump --split-3 --gzip -O <outdir> <sra_file>
  fasterq-dump 为官方推荐的高速替代（-e 线程 / -t 临时目录）。
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

# 子命令 -> 实际可执行文件（bioconda sra-tools 包内三个可执行）
SUBCOMMAND_BIN = {
    "prefetch": "prefetch",
    "fasterq-dump": "fasterq-dump",
    "fastq-dump": "fastq-dump",
}

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "prefetch": "SRA accession -> 本地 .sra 文件（NCBI 下载，nanoseq 默认 -f yes -t http）",
    "fasterq-dump": ".sra -> FASTQ（官方推荐高速版，-e 线程 / -t 临时目录）",
    "fastq-dump": ".sra -> FASTQ（兼容旧版，--split-3 --gzip，nanoseq 脚本原用法）",
}

# 子命令 -> 是否支持 --threads / 位置参数语义
THREADS_BIN = {"fasterq-dump"}


class SraToolsSkill(base.SkillBase):
    software = "sra-tools"
    binary = "prefetch"  # 默认二进制；各子命令自行解析

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_subcommand_bin(self, subcommand: str) -> str:
        bin_name = SUBCOMMAND_BIN.get(subcommand, self.binary)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'（子命令 {subcommand}），请先通过 Conda/Docker/Apptainer 安装 sra-tools。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 sra-tools 命令行。"""
        if subcommand not in SUBCOMMAND_BIN:
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_subcommand_bin(subcommand)
        cmd: list[str] = [binary]

        if subcommand == "prefetch":
            # prefetch [options] <srr_id>   （nanoseq batch_prefetch.sh: -f yes -t http）
            srr = kw.get("srr_id") or kw.get("input")
            if not srr:
                raise ValueError("prefetch 缺少必填参数 srr_id（SRA accession）")
            opts = kw.get("prefetch_options") or "-f yes -t http"
            cmd += str(opts).split()
            outdir = kw.get("output_dir")
            if outdir:
                cmd += ["-O", str(outdir)]
            cmd.append(str(srr))

        elif subcommand == "fasterq-dump":
            # fasterq-dump <sra> [--split-3] [--gzip] -O <outdir> -e <threads> -t <tmpdir> [-o <prefix>]
            sra = kw.get("sra_file") or kw.get("input") or kw.get("srr_id")
            if not sra:
                raise ValueError("fasterq-dump 缺少必填参数 sra_file（.sra 文件或 accession）")
            cmd.append(str(sra))
            if kw.get("split_3", True):
                cmd.append("--split-3")
            if kw.get("gzip", True):
                cmd.append("--gzip")
            outdir = kw.get("output_dir")
            if outdir:
                cmd += ["-O", str(outdir)]
            prefix = kw.get("output") or kw.get("prefix")
            if prefix:
                cmd += ["-o", str(prefix)]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["-e", str(threads)]
            # 临时目录优化（fasterq-dump -t）
            cmd += ["-t", self.tmpdir]

        elif subcommand == "fastq-dump":
            # fastq-dump --split-3 --gzip -O <outdir> <sra_file>   （nanoseq batch_sra_to_fastq*.sh 原用法）
            sra = kw.get("sra_file") or kw.get("input")
            if not sra:
                raise ValueError("fastq-dump 缺少必填参数 sra_file（.sra 文件）")
            if kw.get("split_3", True):
                cmd.append("--split-3")
            if kw.get("gzip", True):
                cmd.append("--gzip")
            outdir = kw.get("output_dir")
            if outdir:
                cmd += ["-O", str(outdir)]
            cmd.append(str(sra))

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
        prog="sra-tools-skill",
        description="sra-tools native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # prefetch
    pp = sub.add_parser("prefetch", help=SUBCOMMANDS["prefetch"])
    pp.add_argument("srr_id", help="SRA accession（如 SRR12345678）")
    pp.add_argument("-O", "--output-dir", help="下载输出目录（默认 <srr_id>/<srr_id>.sra 结构）")
    pp.add_argument("--prefetch-options", default="-f yes -t http", help="prefetch 附加选项（nanoseq 默认 '-f yes -t http'）")
    pp.add_argument("--extra-args", help="透传给 prefetch 的额外参数")
    _add_runtime_opts(pp)

    # fasterq-dump
    pf = sub.add_parser("fasterq-dump", help=SUBCOMMANDS["fasterq-dump"])
    pf.add_argument("input", nargs="?", help="输入 .sra 文件（或 accession；别名 --sra-file）")
    pf.add_argument("--sra-file", help="输入 .sra 文件的别名")
    pf.add_argument("-O", "--output-dir", help="输出目录")
    pf.add_argument("-o", "--output", help="输出文件名/前缀")
    pf.add_argument("--split-3", dest="split_3", action="store_true", help="双端拆分 *_1/*_2（默认开启）")
    pf.add_argument("--no-split-3", dest="split_3", action="store_false", help="关闭 --split-3")
    pf.add_argument("--gzip", dest="gzip", action="store_true", help="输出 .fastq.gz（默认开启）")
    pf.add_argument("--no-gzip", dest="gzip", action="store_false", help="关闭 --gzip")
    pf.add_argument("--extra-args", help="透传给 fasterq-dump 的额外参数")
    _add_runtime_opts(pf)

    # fastq-dump
    pfd = sub.add_parser("fastq-dump", help=SUBCOMMANDS["fastq-dump"])
    pfd.add_argument("input", nargs="?", help="输入 .sra 文件（别名 --sra-file）")
    pfd.add_argument("--sra-file", help="输入 .sra 文件的别名")
    pfd.add_argument("-O", "--output-dir", help="输出目录")
    pfd.add_argument("--split-3", dest="split_3", action="store_true", help="双端拆分 *_1/*_2（默认开启）")
    pfd.add_argument("--no-split-3", dest="split_3", action="store_false", help="关闭 --split-3")
    pfd.add_argument("--gzip", dest="gzip", action="store_true", help="输出 .fastq.gz（默认开启）")
    pfd.add_argument("--no-gzip", dest="gzip", action="store_false", help="关闭 --gzip")
    pfd.add_argument("--extra-args", help="透传给 fastq-dump 的额外参数")
    _add_runtime_opts(pfd)

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
        skill = SraToolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SraToolsSkill()
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

    # prefetch/fastq-dump 的进度输出走 stderr，直接透传
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
