#!/usr/bin/env python3
"""ngsqctoolkit native 标准入口驱动 —— ⚠️ deprecated（历史参考登记）。

NGSQCToolkit（NGS QC Toolkit，NIPGR，Patel & Jain 2012）是 Perl 编写的 Roche 454 /
Illumina NGS QC 脚本集，2014 年 v2.3.3 后停止更新。本驱动是「说明 + argv 构造」型
极简实现：不自行下载/封装全套工具，只为历史留存提供可追溯的官方命令行构造
（参数与官方脚本 help 文本一致，2026-09 经 GitHub 作者 lab 镜像 mjain-lab/NGSQCToolkit
v2.3 原始脚本核对）：

  qc   → perl <root>/QC/IlluQC_PRLL.pl -pe|-se …（高质量过滤，并行版）
  trim → perl <root>/Trimming/TrimmingReads.pl -i …（3' 端质量/长度修剪）
  ambig→ perl <root>/Trimming/AmbiguityFiltering.pl -i …（模糊碱基 N 过滤）

⚠️ 该软件已淘汰：功能被 Trimmomatic / fastp / cutadapt 取代（本仓库 modules/
trimmomatic、fastp、cutadapt 可直接用），官网与下载均已下线（404）。子命令默认
dry_run（只打印命令行不执行），真实执行会打印弃用警告。不要在新流程中使用。

用法：
  python main.py qc --r1 a.fq --r2 b.fq --toolkit-dir ~/sw/NGSQCToolkit_v2.3.3 \
      --adapter N --phred A --outdir qc_out --threads 4
  python main.py trim --input a_filt.fq --outdir t_out --qual-cut 20 --len-cut 70
  python main.py ambig --input a.fq --max-n 0
  python main.py --list-commands
  python main.py --schema
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

#: 弃用提示（run_test 断言此常量含替代软件名）
DEPRECATED_WARNING = (
    "[WARN] NGSQCToolkit 已淘汰（2014 年后无维护，官方页面/下载已下线）："
    "请改用 trimmomatic / fastp / cutadapt，本命令仅作历史复现。"
)

SUBCOMMANDS = {
    "qc": "IlluQC_PRLL.pl 高质量过滤（历史命令构造；⚠️ 已废弃，请改用 trimmomatic/fastp）",
    "trim": "TrimmingReads.pl 3' 端质量/长度修剪（历史命令构造；⚠️ 已废弃，请改用 trimmomatic/fastp）",
    "ambig": "AmbiguityFiltering.pl 模糊碱基 N 过滤（历史命令构造；⚠️ 已废弃，请改用 fastp/cutadapt）",
}

PHDRED_VARIANTS = {
    "1": "Sanger (Phred+33, 33-73)",
    "2": "Solexa (Phred+64, 59-104)",
    "3": "Illumina 1.3+ (Phred+64, 64-104)",
    "4": "Illumina 1.5+ (Phred+64, 66-104)",
    "5": "Illumina 1.8+ (Phred+33, 33-74)",
    "A": "Automatic detection",
}


def _resolve_toolkit_dir(explicit: str | None) -> str:
    """解析 NGSQCToolkit 解压根目录：显式参数 > 环境变量 NGSQCTOOLKIT_ROOT。"""
    root = explicit or os.environ.get("NGSQCTOOLKIT_ROOT")
    if not root:
        raise RuntimeError(
            "需要 NGSQCToolkit 解压根目录（--toolkit-dir 或环境变量 NGSQCTOOLKIT_ROOT）；"
            "历史复现安装见 native/install.sh（官网 zip 已 404，走 GitHub 镜像）"
        )
    return os.path.abspath(os.path.expanduser(str(root)))


class NgsQCToolkitSkill(base.SkillBase):
    software = "ngsqctoolkit"
    binary = "perl"

    def _script(self, toolkit_dir: str, rel: str) -> str:
        p = Path(toolkit_dir) / rel
        if not p.exists():
            raise RuntimeError(f"未找到官方脚本 {p}（toolkit_dir 指向解压根目录？）")
        return str(p)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造历史官方脚本命令行（不自行执行下载等逻辑）。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        perl = self._resolve_binary()
        root = _resolve_toolkit_dir(kw.get("toolkit_dir"))

        if subcommand == "qc":
            return self._cmd_qc(perl, root, **kw)
        if subcommand == "trim":
            return self._cmd_trim(perl, root, **kw)
        return self._cmd_ambig(perl, root, **kw)

    # -- qc：IlluQC_PRLL.pl（官方 help 经 GitHub 镜像 v2.3 核对，2026-09） ---------- #
    def _cmd_qc(self, perl: str, root: str, **kw) -> list[str]:
        r1, r2 = kw.get("r1"), kw.get("r2")
        single = kw.get("input")
        if not (r1 and r2) and not single:
            raise RuntimeError("qc 需要 --r1/--r2（PE）或 --input（SE）")
        if (r1 and r2) and single:
            raise RuntimeError("qc 的 PE（--r1/--r2）与 SE（--input）不能同时给出")

        outdir = kw.get("outdir")
        if not outdir:
            raise RuntimeError("qc 需要 --outdir（-o 输出目录；历史默认 IlluQC_Filtered_files）")

        cmd = [perl, self._script(root, "QC/IlluQC_PRLL.pl")]
        if single:
            cmd += ["-se", os.path.abspath(single),
                    str(kw.get("adapter") or "N"), str(kw.get("phred") or "A")]
        else:
            cmd += ["-pe", os.path.abspath(r1), os.path.abspath(r2),
                    str(kw.get("adapter") or "N"), str(kw.get("phred") or "A")]
        # QC 选项（官方默认：-l 70 HQ 长度百分比阈值 / -s 20 质量阈值 / -c 1 CPU）
        cmd += ["-l", str(int(kw.get("len_cut") or 70)),
                "-s", str(int(kw.get("qual_cut") or 20)),
                "-c", str(int(kw.get("threads") or 1)),
                "-o", os.path.abspath(outdir)]
        if kw.get("gzip"):
            cmd += ["-z", "g"]
        return cmd

    # -- trim：TrimmingReads.pl ------------------------------------------------ #
    def _cmd_trim(self, perl: str, root: str, **kw) -> list[str]:
        inp = kw.get("input")
        if not inp:
            raise RuntimeError("trim 需要 --input（-i 输入 FASTQ/FASTA）")
        cmd = [perl, self._script(root, "Trimming/TrimmingReads.pl"),
               "-i", os.path.abspath(inp)]
        if kw.get("r2"):
            cmd += ["-irev", os.path.abspath(kw["r2"])]
        # -l/-r（固定截短）与 -q（质量截短）互斥；本驱动用 -q/-n 主路径
        if kw.get("left_trim"):
            cmd += ["-l", str(int(kw["left_trim"]))]
        if kw.get("right_trim"):
            cmd += ["-r", str(int(kw["right_trim"]))]
        if kw.get("qual_cut") is not None:
            cmd += ["-q", str(int(kw["qual_cut"]))]
        if kw.get("len_cut") is not None:
            cmd += ["-n", str(int(kw["len_cut"]))]
        if kw.get("outdir"):
            cmd += ["-o", os.path.abspath(kw["outdir"])]
        return cmd

    # -- ambig：AmbiguityFiltering.pl ------------------------------------------ #
    def _cmd_ambig(self, perl: str, root: str, **kw) -> list[str]:
        inp = kw.get("input")
        if not inp:
            raise RuntimeError("ambig 需要 --input（-i 输入 FASTQ/FASTA）")
        cmd = [perl, self._script(root, "Trimming/AmbiguityFiltering.pl"),
               "-i", os.path.abspath(inp)]
        if kw.get("r2"):
            cmd += ["-irev", os.path.abspath(kw["r2"])]
        # 官方：-c/-p/-t5/-t3 四者任选其一（默认 -c 0 允许 0 个 N）
        mode = 0
        if kw.get("percent_n") is not None:
            cmd += ["-p", str(int(kw["percent_n"]))]
            mode += 1
        elif kw.get("trim5"):
            cmd += ["-t5"]
            mode += 1
        elif kw.get("trim3"):
            cmd += ["-t3"]
            mode += 1
        else:
            cmd += ["-c", str(int(kw.get("max_n") if kw.get("max_n") is not None else 0))]
            mode += 1
        if kw.get("len_cut") is not None:
            cmd += ["-n", str(int(kw["len_cut"]))]
        if kw.get("outdir"):
            cmd += ["-o", os.path.abspath(kw["outdir"])]
        if mode > 1:
            raise RuntimeError("ambig 的 -c/-p/-t5/-t3 只能选其一（官方限制）")
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _threads_arg(value: str) -> int:
    try:
        n = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--toolkit-dir", help="NGSQCToolkit 解压根目录（含 QC/ Trimming/；缺省读 $NGSQCTOOLKIT_ROOT）")
    p.add_argument("--threads", type=_threads_arg, default=None, help="线程数（qc -c CPU 数）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--execute", action="store_true",
                   help="真实执行构造的命令（默认 dry_run 只打印；deprecated 工具不建议真实运行）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ngsqctoolkit-skill",
        description="NGSQCToolkit native 技能驱动（⚠️ deprecated，仅历史 argv 构造参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    q = sub.add_parser("qc", help=SUBCOMMANDS["qc"])
    q.add_argument("--r1", help="PE R1（-pe 第 1 输入）")
    q.add_argument("--r2", help="PE R2（-pe 第 2 输入）")
    q.add_argument("--input", help="SE 输入（-se；与 --r1/--r2 二选一）")
    q.add_argument("--adapter", default="N", help="引物/接头库：内置库编号或 N=不过滤或序列文件")
    q.add_argument("--phred", default="A", choices=sorted(PHDRED_VARIANTS),
                   help="FASTQ 变体：1=Sanger 2=Solexa 3/4=Illumina(Phred+64) 5=Illumina1.8+ A=自动（默认）")
    q.add_argument("--qual-cut", type=int, default=20, help="-s 高质量 PHRED 阈值（默认 20）")
    q.add_argument("--len-cut", type=int, default=70, help="-l HQ 长度百分比阈值（默认 70）")
    q.add_argument("--outdir", help="-o 输出目录（历史默认 IlluQC_Filtered_files）")
    q.add_argument("--gzip", action="store_true", help="-z g 输出 gzip 压缩")
    _add_runtime_opts(q)

    t = sub.add_parser("trim", help=SUBCOMMANDS["trim"])
    t.add_argument("--input", help="-i 输入 reads 文件（FASTQ/FASTA）")
    t.add_argument("--r2", help="-irev PE 反向 reads")
    t.add_argument("--left-trim", type=int, default=None, help="-l 从 5' 端固定截短 N 碱基")
    t.add_argument("--right-trim", type=int, default=None, help="-r 从 3' 端固定截短 N 碱基")
    t.add_argument("--qual-cut", type=int, default=None, help="-q 3' 端质量截短阈值（与 -l/-r 互斥）")
    t.add_argument("--len-cut", type=int, default=None, help="-n 短于此长度的 reads 丢弃")
    t.add_argument("--outdir", help="-o 输出文件名/路径")
    _add_runtime_opts(t)

    a = sub.add_parser("ambig", help=SUBCOMMANDS["ambig"])
    a.add_argument("--input", help="-i 输入 reads 文件（FASTQ/FASTA）")
    a.add_argument("--r2", help="-irev PE 反向 reads")
    g = a.add_mutually_exclusive_group()
    g.add_argument("--max-n", type=int, default=0, help="-c 允许的最大 N 数（默认 0；四选一）")
    g.add_argument("--percent-n", type=int, default=None, help="-p 允许的最大 N 百分比（四选一）")
    g.add_argument("--trim5", action="store_true", help="-t5 修剪 5' 端 N（四选一）")
    g.add_argument("--trim3", action="store_true", help="-t3 修剪 3' 端 N（四选一）")
    a.add_argument("--len-cut", type=int, default=None, help="-n 短于此长度的序列丢弃")
    a.add_argument("--outdir", help="-o 输出文件名/路径")
    _add_runtime_opts(a)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        print("# NGSQCToolkit（⚠️ deprecated，仅历史参考）支持子命令：")
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = NgsQCToolkitSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = NgsQCToolkitSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "toolkit_dir", "threads", "tmpdir", "execute")
          and v is not None}
    kw["toolkit_dir"] = ns.toolkit_dir
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print(" ".join(cmd))
    if not ns.execute:
        print(DEPRECATED_WARNING, file=sys.stderr)
        print("[INFO] dry_run：仅打印命令行（历史参考）；加 --execute 才真实执行。", file=sys.stderr)
        return 0

    print(DEPRECATED_WARNING, file=sys.stderr)
    try:
        result = base.run_command(cmd, env=skill.env_vars)
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
