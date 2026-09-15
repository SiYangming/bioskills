#!/usr/bin/env python3
"""gapfiller native 标准入口驱动（Perl GapFiller.pl，v1.11 三代修改版）。

GapFiller 是 BaseClear（Boetzer & Pirovano）的 scaffold 补洞工具，Perl 单文件脚本 GapFiller.pl，
CLI 形如：
    GapFiller.pl -l library.txt -s genome.fa [-b standard_output] [-m 29] [-o 2] [-r 0.7]
                 [-d 50] [-n 10] [-t 10] [-i 10] [-g 1] [-T 4]
依赖 bowtie/bwa（脚本按自身目录 $Bin/bowtie/bowtie、$Bin/bwa/bwa 查找比对器）。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py fill -l library.txt -s genome.fa --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema | --list-commands

线程优先级：用户显式 --threads > optimization.per_subcommand_threads.fill > default_cpus（注入 -T）。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "fill": "GapFiller.pl 补洞主流程（-l library.txt -s genome.fa -T N，借助 bowtie/bwa 局部延伸）",
}

# GapFiller.pl 候选位置（{conda} 渲染为 CONDA_PREFIX）
_SCRIPT_GLOBS = [
    "{conda}/bin/GapFiller.pl",
    "{conda}/share/gapfiller*/GapFiller.pl",
    "~/software/GapFiller_v1-11_linux-x86_64/GapFiller.pl",
    "~/software/gapfiller*/GapFiller.pl",
    "/opt/gapfiller/GapFiller.pl",
]


class GapFillerSkill(base.SkillBase):
    software = "gapfiller"
    binary = "GapFiller.pl"

    def _resolve_binary(self) -> str:
        """定位 GapFiller.pl 脚本（惰性；测试用 monkeypatch 覆盖，不依赖工具已安装）。"""
        env_home = os.environ.get("GAPFILLER_HOME")
        if env_home:
            cand = Path(env_home) / "GapFiller.pl"
            if cand.is_file():
                return str(cand)
        path = base.which("GapFiller.pl")
        if path:
            return path
        conda = os.environ.get("CONDA_PREFIX", "")
        for pat in _SCRIPT_GLOBS:
            p = pat.format(conda=conda)
            if p.startswith("~"):
                p = str(Path(p).expanduser())
            hits = sorted(glob.glob(p))
            if hits:
                return hits[0]
        raise RuntimeError(
            "未找到 GapFiller.pl；请安装（native/install.sh 源码部署，或自建容器），"
            "或设置 GAPFILLER_HOME 指向含 GapFiller.pl 的目录"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        library = kw.get("library")
        scaffold = kw.get("scaffold")
        if not library:
            raise ValueError("fill 缺少必填参数 library（-l <文库表文件>）")
        if not scaffold:
            raise ValueError("fill 缺少必填参数 scaffold（-s <scaffold FASTA>）")

        cmd: list[str] = [self._resolve_binary(), "-l", str(library), "-s", str(scaffold)]

        # 数值/字符串白名单参数：显式给出才注入（默认值语义以 GapFiller.pl USAGE 为准）
        for key, flag in (
            ("min_overlap", "-m"),
            ("min_reads_per_base", "-o"),
            ("min_base_ratio", "-r"),
            ("max_diff", "-d"),
            ("min_tig_overlap", "-n"),
            ("trim", "-t"),
            ("iterations", "-i"),
            ("bowtie_gaps", "-g"),
            ("base_name", "-b"),
        ):
            val = kw.get(key)
            if val is not None:
                cmd += [flag, str(val)]

        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-T", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖线程数（注入 -T）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gapfiller-skill",
        description="gapfiller native 技能驱动（Perl GapFiller.pl v1.11；自动线程 -T 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pf = sub.add_parser("fill", help=SUBCOMMANDS["fill"])
    pf.add_argument("-l", "--library", required=True,
                    help="文库表文件（每行：文库名 比对工具 reads1 reads2 插入长度 误差 方向）")
    pf.add_argument("-s", "--scaffold", required=True, help="待补洞的 scaffold FASTA")
    pf.add_argument("-b", "--base-name", dest="base_name",
                    help="输出目录/文件名前缀（默认 standard_output）")
    pf.add_argument("-m", "--min-overlap", dest="min_overlap", type=int,
                    help="与 gap 边缘最小重叠碱基数（默认 29）")
    pf.add_argument("-o", "--min-reads-per-base", dest="min_reads_per_base", type=int,
                    help="调用一个碱基所需最小 reads 数（默认 2）")
    pf.add_argument("-r", "--min-base-ratio", dest="min_base_ratio", type=float,
                    help="单碱基延伸 reads 百分比阈值（默认 0.7）")
    pf.add_argument("-d", "--max-diff", dest="max_diff", type=int,
                    help="gapsize 与已填补碱基数的最大差异（默认 50）")
    pf.add_argument("-n", "--min-tig-overlap", dest="min_tig_overlap", type=int,
                    help="合并相邻序列所需最小 contig 重叠（默认 10）")
    pf.add_argument("-t", "--trim", type=int, help="序列首尾裁剪的 reads 数（默认 10）")
    pf.add_argument("-i", "--iterations", type=int, help="补洞迭代次数（默认 10）")
    pf.add_argument("-g", "--bowtie-gaps", dest="bowtie_gaps", type=int,
                    help="bowtie 比对允许的最大 gap 数（默认 1）")
    pf.add_argument("--extra-args", dest="extra_args", help="透传给 GapFiller.pl 的额外参数")
    _add_runtime_opts(pf)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = GapFillerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GapFillerSkill()
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
