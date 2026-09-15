#!/usr/bin/env python3
"""kallisto native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py index -i kallisto_index Trinity.fasta
   python main.py quant -i kallisto_index -b 100 -o kallisto_out/A1 A1.1.fastq A1.2.fastq --threads 8
   python main.py inspect kallisto_index
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  index     kallisto index -i <index> [-k <kmer>] [-t N] <transcripts.fa>
  quant     kallisto quant -i <index> -o <outdir> -b <N> -t N (<r1> <r2> | --single -l <len> -s <sd> <reads>)
  inspect   kallisto inspect <index>
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "index": "构建转录组伪比对（pseudoalignment）索引",
    "quant": "转录本定量（伪比对，支持双端/单端）",
    "inspect": "查看 kallisto 索引信息",
}

# 支持线程注入的子命令（kallisto index/quant 用 -t）
SUPPORTS_THREADS = {"index", "quant"}


class KallistoSkill(base.SkillBase):
    software = "kallisto"
    binary = "kallisto"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 kallisto 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "index":
            index = kw.get("index") or kw.get("output")
            if not index:
                raise ValueError("index 缺少必填参数 index（-i，输出索引路径）")
            transcripts = kw.get("transcripts") or kw.get("input")
            if not transcripts:
                raise ValueError("index 缺少必填参数 transcripts（转录本 FASTA）")
            cmd: list[str] = [binary, "index", "-i", str(index)]
            if kw.get("kmer") is not None:
                cmd += ["-k", str(kw["kmer"])]
            cmd += ["-t", str(threads)]
            cmd.append(str(transcripts))

        elif subcommand == "quant":
            index = kw.get("index")
            if not index:
                raise ValueError("quant 缺少必填参数 index（-i）")
            outdir = kw.get("output")
            if not outdir:
                raise ValueError("quant 缺少必填参数 output（-o，输出目录）")
            cmd = [binary, "quant", "-i", str(index), "-o", str(outdir)]
            cmd += ["-b", str(kw.get("bootstrap") if kw.get("bootstrap") is not None else 100)]
            cmd += ["-t", str(threads)]
            if kw.get("single"):
                cmd.append("--single")
                if kw.get("fragment_length") is not None:
                    cmd += ["-l", str(kw["fragment_length"])]
                if kw.get("fragment_sd") is not None:
                    cmd += ["-s", str(kw["fragment_sd"])]
                reads = kw.get("reads")
                if not reads:
                    raise ValueError("单端 quant 缺少必填参数 reads（--single 模式）")
                cmd.append(str(reads))
            else:
                left = kw.get("left")
                right = kw.get("right")
                if not left or not right:
                    raise ValueError("双端 quant 缺少必填参数 left/right（位置参数 r1 r2）")
                cmd += [str(left), str(right)]

        else:  # inspect
            index = kw.get("index") or kw.get("input")
            if not index:
                raise ValueError("inspect 缺少必填参数 index（索引路径）")
            cmd = [binary, "inspect", str(index)]

        # 高级透传（慎用）
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
        prog="kallisto-skill",
        description="kallisto native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("transcripts", nargs="?", help="转录本 FASTA（别名 --transcripts）")
    pi.add_argument("-i", "--index", required=True, help="输出索引路径")
    pi.add_argument("-k", "--kmer", type=int, help="k-mer 长度（默认 31）")
    pi.add_argument("--extra-args", help="透传给 kallisto 的额外参数")
    _add_runtime_opts(pi)

    # quant
    pq = sub.add_parser("quant", help=SUBCOMMANDS["quant"])
    pq.add_argument("-i", "--index", required=True, help="kallisto 索引")
    pq.add_argument("-o", "--output", required=True, help="输出目录")
    pq.add_argument("-b", "--bootstrap", type=int, default=100, help="bootstrap 次数（默认 100）")
    pq.add_argument("--single", action="store_true", help="单端模式")
    pq.add_argument("-l", "--fragment-length", type=float, help="单端平均片段长度")
    pq.add_argument("-s", "--fragment-sd", type=float, help="单端片段长度标准差")
    pq.add_argument("left", nargs="?", help="双端 r1（或单端 reads）")
    pq.add_argument("right", nargs="?", help="双端 r2")
    pq.add_argument("--extra-args", help="透传给 kallisto 的额外参数")
    _add_runtime_opts(pq)

    # inspect
    pn = sub.add_parser("inspect", help=SUBCOMMANDS["inspect"])
    pn.add_argument("index", help="kallisto 索引路径")
    pn.add_argument("--extra-args", help="透传给 kallisto 的额外参数")
    _add_runtime_opts(pn)

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
        skill = KallistoSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = KallistoSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    # 单端模式：位置参数 left 复用为 reads
    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "quant" and ns.single and ns.left:
        kw["reads"] = ns.left
        kw.pop("left", None)
        kw.pop("right", None)

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
