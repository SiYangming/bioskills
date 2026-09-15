#!/usr/bin/env python3
"""gce native 标准入口驱动（GCE 1.0.0；BGI 基因组特征估计）。

GCE (Genome Characteristics Estimation) 基于 k-mer 频率估计基因组大小/重复/杂合度，
包含两支程序：
  kmer_freq_hash  reads 列表 -> k-mer 频数统计（<prefix>.freq.gz / <prefix>.freq.stat）
  gce             <prefix>.freq.stat -> 基因组特征估计（stdout 表 + stderr 日志）

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py kmer_freq_hash -l reads.list -k 21 -p out --threads 8
   python main.py gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 -o out.table --log out.log
   python main.py gce -f out.freq.stat -g 273206457 -H --log out.h1.log
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对照文档 docs/04.md 第 42-117 行）：
  kmer_freq_hash -k 21 -l reads.list -t 8 -i 80000000 -o 0 -p out
  gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 [-H 1] > out.table 2> out.log

⚠️ GCE 为历史遗留工具（BGI 官方源 2026-09 已停服；bioconda/quay/depot 均无官方包/镜像）；
   宿主机安装见 README「环境安装」（native/install.sh 源码编译）。
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
    "kmer_freq_hash": "reads 列表 -> k-mer 频数统计（<prefix>.freq.gz / <prefix>.freq.stat）",
    "gce": "k-mer 深度频率文件 -> 基因组大小/重复/杂合度估计（stdout 表 + stderr 日志）",
}

# 子命令 -> 真实可执行名（GCE 1.0.0 包内两支程序）
_BINARIES = {"kmer_freq_hash": "kmer_freq_hash", "gce": "gce"}


class GceSkill(base.SkillBase):
    software = "gce"
    binary = "gce"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）"
            )

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（kmer_freq_hash / gce），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 GCE 1.0.0（官方无 conda/容器渠道，"
                f"源码编译见 README「环境安装」：bash native/install.sh）并把其目录加入 PATH。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """kmer_freq_hash / gce：构造 GCE 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)
        if subcommand == "kmer_freq_hash":
            return self._build_kmer_freq(bin_path, **kw)
        if subcommand == "gce":
            return self._build_gce(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- kmer_freq_hash ---------------------------------------------------- #
    def _build_kmer_freq(self, bin_path: str, **kw) -> list[str]:
        reads_list = kw.get("reads_list") or kw.get("input")
        if not reads_list:
            raise RuntimeError("kmer_freq_hash 需要 --reads-list（-l reads 路径列表）")
        prefix = kw.get("output_prefix")
        if not prefix:
            raise RuntimeError("kmer_freq_hash 需要 --output-prefix（-p 输出前缀）")
        threads = self._effective_threads("kmer_freq_hash", kw.get("threads"))

        cmd: list[str] = [
            bin_path,
            "-k", str(int(kw.get("kmer_size") or 17)),
            "-l", str(reads_list),
            "-t", str(threads),
        ]
        if kw.get("init_hash") is not None:
            cmd += ["-i", str(int(kw["init_hash"]))]
        # -o 1 导出每个 k-mer 序列（耗时）；默认 0 只产出 freq.gz/freq.stat 统计
        cmd += ["-o", "1" if kw.get("dump_kmers") else "0", "-p", str(prefix)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- gce --------------------------------------------------------------- #
    def _build_gce(self, bin_path: str, **kw) -> list[str]:
        freq_stat = kw.get("freq_stat") or kw.get("input")
        if not freq_stat:
            raise RuntimeError("gce 需要 --freq-stat（-f k-mer 深度频率文件）")

        cmd: list[str] = [bin_path, "-f", str(freq_stat)]
        if kw.get("uniq_coverage") is not None:
            cmd += ["-c", str(int(kw["uniq_coverage"]))]
        if kw.get("genome_size") is not None:
            cmd += ["-g", str(int(kw["genome_size"]))]
        if kw.get("est_mode") is not None:
            cmd += ["-m", str(int(kw["est_mode"]))]
        if kw.get("max_depth") is not None:
            cmd += ["-D", str(int(kw["max_depth"]))]
        if kw.get("bias") is not None:
            cmd += ["-b", str(int(kw["bias"]))]
        if kw.get("hybrid"):
            cmd += ["-H", "1"]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd  # 表写 stdout，日志写 stderr（由 main() 重定向到 output/log）

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gce-skill",
        description="gce native 技能驱动（kmer_freq_hash 计数 + gce 基因组特征估计）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # kmer_freq_hash
    pk = sub.add_parser("kmer_freq_hash", help=SUBCOMMANDS["kmer_freq_hash"])
    pk.add_argument("-l", "--reads-list", required=True, help="reads 文件路径列表（每行一个）")
    pk.add_argument("-k", "--kmer-size", type=int, default=17, help="k-mer 长度（9~27，默认 17）")
    pk.add_argument("-p", "--output-prefix", required=True, help="输出前缀")
    pk.add_argument("-i", "--init-hash", type=int, help="每线程初始 hash 表大小（如 80000000）")
    pk.add_argument("--dump-kmers", action="store_true", help="导出每个 k-mer 序列（-o 1）")
    pk.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pk)

    # gce
    pg = sub.add_parser("gce", help=SUBCOMMANDS["gce"])
    pg.add_argument("-f", "--freq-stat", required=True, help="k-mer 深度频率文件（.freq.stat）")
    pg.add_argument("-c", "--uniq-coverage", type=int, help="unique k-mer 期望深度")
    pg.add_argument("-g", "--genome-size", type=int, help="总 k-mer 数")
    pg.add_argument("-m", "--est-mode", type=int, choices=[0, 1], help="0=离散（默认）/1=连续")
    pg.add_argument("-D", "--max-depth", type=int, help="连续模型峰间距（precision）")
    pg.add_argument("-b", "--bias", type=int, choices=[0, 1], help="测序偏好 1=有 / 0=无")
    pg.add_argument("-H", "--hybrid", action="store_true", help="杂合模式（追加 -H 1）")
    pg.add_argument("-o", "--output", help="估计结果表输出路径（默认打印 stdout）")
    pg.add_argument("--log", help="运行日志输出路径（gce stderr）")
    pg.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅 kmer_freq_hash 生效）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = GceSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GceSkill()
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

    # gce：stdout → 结果表，stderr → 日志（文档用 > out.table 2> out.log）
    if ns.subcommand == "gce":
        if getattr(ns, "output", None) and result.stdout:
            with open(ns.output, "w", encoding="utf-8") as fh:
                fh.write(result.stdout)
        if getattr(ns, "log", None) and result.stderr:
            with open(ns.log, "w", encoding="utf-8") as fh:
                fh.write(result.stderr)
        elif result.stderr:
            sys.stderr.write(result.stderr)
    elif result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
