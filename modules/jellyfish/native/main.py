#!/usr/bin/env python3
"""jellyfish native 标准入口驱动（Jellyfish 2.3.0 k-mer 计数）。

覆盖 Jellyfish 2.x 高频子命令：
  count  jellyfish count -C -m <k> -s <size> -t <N> -o <mer_counts.jf> <reads...>
  histo  jellyfish histo -t <N> <mer_counts.jf>            # stdout 直方图
  stats  jellyfish stats <mer_counts.jf>
  query  jellyfish query <mer_counts.jf> <kmer>
  dump   jellyfish dump <mer_counts.jf>
  merge  jellyfish merge -o <out.jf> <hash1.jf> <hash2.jf> ...

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py count -m 21 -s 100M -C -o mer_counts.jf reads_1.fastq reads_2.fastq --threads 4
   python main.py histo mer_counts.jf -o mer_counts.histo --threads 4
   python main.py stats mer_counts.jf
   python main.py query mer_counts.jf ATGCATGCATGCATGCATGCA
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：jellyfish 已安装（官方 release 静态二进制 jellyfish-linux / conda kmer-jellyfish=2.3.0 /
quay.io/biocontainers/kmer-jellyfish，见 README「环境安装」）；count/histo 自动注入线程 -t。
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

SUBCOMMANDS = {
    "count": "reads -> k-mer 计数（-C -m <k> -s <size> -t <N> -o <mer_counts.jf>）",
    "histo": "k-mer 计数文件 -> 频率直方图（stdout，可 -o 重定向）",
    "stats": "k-mer 计数文件 -> 统计信息（stdout，可 -o 重定向）",
    "query": "查询特定 k-mer 的出现次数（stdout，可 -o 重定向）",
    "dump": "导出所有 k-mer 及其计数（stdout，可 -o 重定向）",
    "merge": "合并多个 k-mer 计数文件（-o <out.jf>）",
}

# 输出写 stdout、需 main() 重定向到 -o 文件的子命令
_STDOUT_SUBCOMMANDS = {"histo", "stats", "query", "dump"}


class JellyfishSkill(base.SkillBase):
    software = "jellyfish"
    binary = "jellyfish"

    @staticmethod
    def _as_list(value) -> list[str]:
        if value is None:
            return []
        if isinstance(value, (list, tuple)):
            return [str(v) for v in value]
        return str(value).split()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构建 jellyfish 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))
        kw = {k: v for k, v in kw.items() if k != "threads"}

        if subcommand == "count":
            return self._build_count(binary, threads, **kw)
        if subcommand == "histo":
            return self._build_histo(binary, threads, **kw)
        if subcommand == "stats":
            return self._build_simple(binary, "stats", **kw)
        if subcommand == "query":
            return self._build_query(binary, **kw)
        if subcommand == "dump":
            return self._build_simple(binary, "dump", **kw)
        return self._build_merge(binary, **kw)

    # -- count ------------------------------------------------------------- #
    def _build_count(self, binary: str, threads: int, **kw) -> list[str]:
        reads = self._as_list(kw.get("reads") or kw.get("input"))
        if not reads:
            raise RuntimeError("count 需要输入序列文件（reads，可多个）")
        cmd: list[str] = [binary, "count"]
        if kw.get("canonical", True):
            cmd.append("-C")
        cmd += ["-m", str(int(kw.get("kmer_size") or 21))]
        if kw.get("hash_size") is not None:
            cmd += ["-s", str(kw["hash_size"])]
        if kw.get("counts_threshold") is not None:
            cmd += ["-c", str(int(kw["counts_threshold"]))]
        cmd += ["-t", str(threads)]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        cmd += reads
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- histo ------------------------------------------------------------- #
    def _build_histo(self, binary: str, threads: int, **kw) -> list[str]:
        counts = kw.get("counts") or kw.get("input")
        if not counts:
            raise RuntimeError("histo 需要输入 .jf 计数文件（counts）")
        cmd: list[str] = [binary, "histo", "-t", str(threads)]
        if kw.get("histogram_low") is not None:
            cmd += ["-l", str(int(kw["histogram_low"]))]
        if kw.get("histogram_high") is not None:
            cmd += ["-h", str(int(kw["histogram_high"]))]
        if kw.get("histogram_increment") is not None:
            cmd += ["-i", str(int(kw["histogram_increment"]))]
        cmd.append(str(counts))
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- stats / dump ------------------------------------------------------ #
    def _build_simple(self, binary: str, sub: str, **kw) -> list[str]:
        counts = kw.get("counts") or kw.get("input")
        if not counts:
            raise RuntimeError(f"{sub} 需要输入 .jf 计数文件（counts）")
        cmd: list[str] = [binary, sub, str(counts)]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- query ------------------------------------------------------------- #
    def _build_query(self, binary: str, **kw) -> list[str]:
        counts = kw.get("counts") or kw.get("input")
        if not counts:
            raise RuntimeError("query 需要输入 .jf 计数文件（counts）")
        cmd: list[str] = [binary, "query", str(counts)]
        if kw.get("kmer"):
            cmd.append(str(kw["kmer"]))
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- merge ------------------------------------------------------------- #
    def _build_merge(self, binary: str, **kw) -> list[str]:
        inputs = self._as_list(kw.get("merge_inputs") or kw.get("input"))
        if not inputs:
            raise RuntimeError("merge 需要待合并的 .jf 文件（merge_inputs，可多个）")
        cmd: list[str] = [binary, "merge"]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        cmd += inputs
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
        prog="jellyfish-skill",
        description="jellyfish native 技能驱动（k-mer 计数与直方图/统计/查询/导出/合并）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # count
    pc = sub.add_parser("count", help=SUBCOMMANDS["count"])
    pc.add_argument("reads", nargs="+", help="输入序列文件（FASTA/FASTQ，可多个）")
    pc.add_argument("-m", "--kmer-size", type=int, default=21, help="k-mer 长度（默认 21）")
    pc.add_argument("-s", "--hash-size", default="100M", help="初始 hash 表大小（如 100M）")
    pc.add_argument("-c", "--counts-threshold", type=int, help="计数位宽（默认 2）")
    pc.add_argument("-o", "--output", help="输出 .jf 计数文件")
    pc.add_argument("--no-canonical", dest="canonical", action="store_false",
                    help="关闭 -C（不合并正/负链 k-mer）")
    pc.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pc)

    # histo
    ph = sub.add_parser("histo", help=SUBCOMMANDS["histo"])
    ph.add_argument("counts", help="输入 .jf 计数文件")
    ph.add_argument("-l", "--histogram-low", type=int, help="直方图最小计数")
    ph.add_argument("--histogram-high", type=int, help="直方图最大计数（jellyfish 默认 10000）")
    ph.add_argument("-i", "--histogram-increment", type=int, help="直方图计数步长")
    ph.add_argument("-o", "--output", help="输出直方图文件（默认打印 stdout）")
    ph.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(ph)

    # stats
    ps = sub.add_parser("stats", help=SUBCOMMANDS["stats"])
    ps.add_argument("counts", help="输入 .jf 计数文件")
    ps.add_argument("-o", "--output", help="输出统计文件（默认打印 stdout）")
    ps.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(ps)

    # query
    pq = sub.add_parser("query", help=SUBCOMMANDS["query"])
    pq.add_argument("counts", help="输入 .jf 计数文件")
    pq.add_argument("kmer", nargs="?", help="待查询的 k-mer 序列")
    pq.add_argument("-o", "--output", help="输出结果文件（默认打印 stdout）")
    pq.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pq)

    # dump
    pd = sub.add_parser("dump", help=SUBCOMMANDS["dump"])
    pd.add_argument("counts", help="输入 .jf 计数文件")
    pd.add_argument("-o", "--output", help="输出文件（默认打印 stdout）")
    pd.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pd)

    # merge
    pm = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pm.add_argument("merge_inputs", nargs="+", help="待合并的 .jf 计数文件（可多个）")
    pm.add_argument("-o", "--output", help="输出合并后的 .jf 文件")
    pm.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pm)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（count/histo 生效）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = JellyfishSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = JellyfishSkill()
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

    # 写 stdout 的子命令：可 -o 重定向到文件
    if ns.subcommand in _STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
