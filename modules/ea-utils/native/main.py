#!/usr/bin/env python3
"""ea-utils native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py join R1.fastq R2.fastq -o out. --threads 1
   python main.py mcf adapters.fa reads.fq -o clean.fq -q 30 -l 50
   python main.py stats reads.fastq -x per_base.tsv
   python main.py clipper reads.fastq AGATCGGAAGAGC -o clipped.fastq
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（每个子命令对应一个独立的 ea-utils 可执行文件）：
  join      fastq-join <read1.fq> <read2.fq> [mate.fq] -o <read.%.fq>
  mcf       fastq-mcf [options] <adapters.fa> <reads.fq> [mates1.fq ...]
  stats     fastq-stats [options] <fastq-file>
  clipper   fastq-clipper [options] <fastq-file> <adapters>
说明：ea-utils 各子程序均为单线程，不接受线程参数（fastq-mcf 的 -p 为接头差异百分比，非线程）；
      --threads 作为契约字段被接受但不注入命令行。
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
    "join": "fastq-join：按双端重叠拼接 paired-end reads（QIIME join_paired_ends.py 的底层工具）",
    "mcf": "fastq-mcf：检测并切除接头/引物 + 质量过滤 + 去 N/去重",
    "stats": "fastq-stats：FASTQ 基础统计（reads/碱基数/重复/逐碱基）",
    "clipper": "fastq-clipper：去除一条或多条接头序列（冒号分隔）",
}

# 子命令 -> 对应的 ea-utils 可执行文件
BINARY_BY_SUBCOMMAND = {
    "join": "fastq-join",
    "mcf": "fastq-mcf",
    "stats": "fastq-stats",
    "clipper": "fastq-clipper",
}


class EaUtilsSkill(base.SkillBase):
    software = "ea-utils"
    binary = "fastq-join"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（ea-utils 单线程，仅作契约记录）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_binary_for(self, subcommand: str) -> str:
        """按子命令惰性解析对应可执行文件（找不到抛错；测试可 monkeypatch）。"""
        name = BINARY_BY_SUBCOMMAND.get(subcommand)
        if not name:
            raise ValueError(f"未知子命令: {subcommand}")
        if name == (self.binary or self.software):
            return self._resolve_binary()
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 ea-utils。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 ea-utils 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary_for(subcommand)
        # 契约线程（不注入；ea-utils 无线程参数）
        self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "join":
            read1 = kw.get("read1") or kw.get("input")
            read2 = kw.get("read2")
            if not read1 or not read2:
                raise ValueError("join 缺少必填参数 read1 与 read2（两个 FASTQ）")
            cmd: list[str] = [binary, str(read1), str(read2)]
            mate = kw.get("mate")
            if mate:
                cmd.append(str(mate))
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("verify") is not None:
                cmd += ["-v", str(kw["verify"])]
            if kw.get("pct_diff") is not None:
                cmd += ["-p", str(kw["pct_diff"])]
            if kw.get("min_overlap") is not None:
                cmd += ["-m", str(kw["min_overlap"])]
            if kw.get("report"):
                cmd += ["-r", str(kw["report"])]
            if kw.get("no_revcomp"):
                cmd.append("-R")
            if kw.get("allow_short_insert"):
                cmd.append("-x")

        elif subcommand == "mcf":
            adapters = kw.get("adapters")
            reads = kw.get("reads")
            if not adapters or not reads:
                raise ValueError("mcf 缺少必填参数 adapters（FASTA 或 'n/a'）与 reads（一个或多个 FASTQ）")
            cmd = [binary]
            outs = kw.get("output") or []
            if isinstance(outs, str):
                outs = [outs]
            for out in outs:
                cmd += ["-o", str(out)]
            if kw.get("qual") is not None:
                cmd += ["-q", str(kw["qual"])]
            if kw.get("min_len") is not None:
                cmd += ["-l", str(kw["min_len"])]
            if kw.get("max_len") is not None:
                cmd += ["-L", str(kw["max_len"])]
            if kw.get("scale") is not None:
                cmd += ["-s", str(kw["scale"])]
            if kw.get("threshold") is not None:
                cmd += ["-t", str(kw["threshold"])]
            if kw.get("pct_diff") is not None:
                cmd += ["-p", str(kw["pct_diff"])]
            if kw.get("window") is not None:
                cmd += ["-w", str(kw["window"])]
            if kw.get("qual_mean") is not None:
                cmd += ["--qual-mean", str(kw["qual_mean"])]
            if kw.get("no_defaults"):
                cmd.append("-0")
            cmd.append(str(adapters))
            cmd += [str(r) for r in reads]

        elif subcommand == "stats":
            reads = kw.get("reads") or kw.get("input")
            if not reads:
                raise ValueError("stats 缺少必填参数 reads（一个或多个 FASTQ）")
            if isinstance(reads, str):
                reads = [reads]
            cmd = [binary]
            if kw.get("per_base"):
                cmd += ["-x", str(kw["per_base"])]
            if kw.get("max_cycles") is not None:
                cmd += ["-c", str(kw["max_cycles"])]
            if kw.get("window") is not None:
                cmd += ["-w", str(kw["window"])]
            if kw.get("top_dups") is not None:
                cmd += ["-s", str(kw["top_dups"])]
            if kw.get("no_dups"):
                cmd.append("-D")
            cmd += [str(r) for r in reads]

        else:  # clipper
            reads = kw.get("input")
            adapters = kw.get("adapters")
            if not reads or not adapters:
                raise ValueError("clipper 缺少必填参数 input（FASTQ）与 adapters（冒号分隔的接头序列）")
            cmd = [binary]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("pct_diff") is not None:
                cmd += ["-p", str(kw["pct_diff"])]
            if kw.get("min_len") is not None:
                cmd += ["-l", str(kw["min_len"])]
            cmd += [str(reads), str(adapters)]

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
        prog="ea-utils-skill",
        description="ea-utils native 技能驱动（fastq-join / fastq-mcf / fastq-stats / fastq-clipper）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # join（fastq-join）
    pj = sub.add_parser("join", help=SUBCOMMANDS["join"])
    pj.add_argument("read1", nargs="?", help="R1 FASTQ（别名 --read1）")
    pj.add_argument("read2", nargs="?", help="R2 FASTQ（别名 --read2）")
    pj.add_argument("--read1", help="R1 FASTQ 的别名")
    pj.add_argument("--read2", help="R2 FASTQ 的别名")
    pj.add_argument("--mate", help="可选第 3 个 barcode/mate FASTQ")
    pj.add_argument("-o", "--output", help="输出文件名模板（如 out. 或 out.%.fq）")
    pj.add_argument("-v", "--verify", help="校验 read id 匹配到第 C 个字符（Illumina 用 ' '）")
    pj.add_argument("-p", "--pct-diff", type=int, help="最大差异百分比（默认 8）")
    pj.add_argument("-m", "--min-overlap", type=int, help="最小重叠长度（默认 6）")
    pj.add_argument("-r", "--report", help="verbose stitch length report 输出文件")
    pj.add_argument("--no-revcomp", action="store_true", help="不做反向互补（-R）")
    pj.add_argument("--allow-short-insert", action="store_true", help="允许 insert < read length（-x）")
    pj.add_argument("--extra-args", help="透传给 fastq-join 的额外参数")
    _add_runtime_opts(pj)

    # mcf（fastq-mcf）
    pm = sub.add_parser("mcf", help=SUBCOMMANDS["mcf"])
    pm.add_argument("adapters", nargs="?", help="接头 FASTA（或 'n/a'）")
    pm.add_argument("reads", nargs="*", help="输入 FASTQ（可多个 mates）")
    pm.add_argument("-o", "--output", action="append", help="输出文件（每个输入一个，可重复）")
    pm.add_argument("-q", "--qual", type=int, help="触发碱基切除的质量阈值（默认 10）")
    pm.add_argument("-l", "--min-len", type=int, help="过滤后最小剩余长度（默认 19）")
    pm.add_argument("-L", "--max-len", type=int, help="过滤后最大剩余长度（默认无限制）")
    pm.add_argument("-s", "--scale", type=float, help="接头最小匹配长度的 log 尺度（默认 2.2）")
    pm.add_argument("-t", "--threshold", type=float, help="接头切除 occurrence 阈值（默认 0.25）")
    pm.add_argument("-p", "--pct-diff", type=int, help="最大接头差异百分比（默认 10）")
    pm.add_argument("-w", "--window", type=int, help="质量修剪窗口大小（默认 1）")
    pm.add_argument("--qual-mean", type=float, help="最小平均质量（--qual-mean）")
    pm.add_argument("-0", "--no-defaults", action="store_true", help="关闭全部默认设置（-0）")
    pm.add_argument("--extra-args", help="透传给 fastq-mcf 的额外参数")
    _add_runtime_opts(pm)

    # stats（fastq-stats）
    ps = sub.add_parser("stats", help=SUBCOMMANDS["stats"])
    ps.add_argument("reads", nargs="*", help="输入 FASTQ（可多个）")
    ps.add_argument("-x", "--per-base", help="per-base fastx 统计输出文件")
    ps.add_argument("-c", "--max-cycles", type=int, help="输出质量统计的最大循环数（默认 35）")
    ps.add_argument("-w", "--window", type=int, help="重复 read 统计窗口（默认 2000000）")
    ps.add_argument("-s", "--top-dups", type=int, help="显示 top N 重复 read")
    ps.add_argument("-D", "--no-dups", action="store_true", help="不做重复 read 统计（-D）")
    ps.add_argument("--extra-args", help="透传给 fastq-stats 的额外参数")
    _add_runtime_opts(ps)

    # clipper（fastq-clipper）
    pc = sub.add_parser("clipper", help=SUBCOMMANDS["clipper"])
    pc.add_argument("input", nargs="?", help="输入 FASTQ（别名 --read）")
    pc.add_argument("adapters", nargs="?", help="冒号分隔的接头序列")
    pc.add_argument("--read", help="输入 FASTQ 的别名")
    pc.add_argument("-o", "--output", help="输出 FASTQ（默认 stdout）")
    pc.add_argument("-p", "--pct-diff", type=int, help="最大差异百分比（默认 10）")
    pc.add_argument("-l", "--min-len", type=int, help="最小剩余长度")
    pc.add_argument("--extra-args", help="透传给 fastq-clipper 的额外参数")
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（ea-utils 单线程，仅契约字段）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = EaUtilsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EaUtilsSkill()
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
