#!/usr/bin/env python3
"""bwa native 标准入口驱动。

bwa（Burrows-Wheeler Aligner）是 C 程序，CLI 形如：
    bwa index [-a bwtsw] <ref.fa>
    bwa mem [-t N] [-M] [-R '@RG...'] <idxbase> <R1.fq> [R2.fq]
    bwa aln  [-t N] [-f out.sai] <idxbase> <reads.fq>
    bwa samse [-f out.sam] <idxbase> <r1.sai> <r1.fq>
    bwa sampe [-f out.sam] <idxbase> <r1.sai> <r2.sai> <r1.fq> <r2.fq>
conda / brew / biocontainer 提供同一 `bwa` 可执行名。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py index ref.fa --index-algorithm bwtsw
   python main.py mem --index ref.fa --reads1 s_R1.fq.gz --reads2 s_R2.fq.gz \
       --threads 16 -M -R "@RG\tID:s1\tSM:s1"
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位 bwa：PATH 上 `bwa`（bioconda / brew / 官方 make 产物均可）。
- -t 线程自动注入（mem 默认 8 / aln 默认 4，可 --threads 覆盖）；TMPDIR 经 env 注入。
- bwa mem 的 SAM 走 stdout（原生行为，可 shell 重定向 / 管道给 samtools）；
  aln / samse / sampe 支持 -f 落盘。
- --dry-run 仅构造并打印 argv（不执行），供降级 argv 构造回归。
"""

from __future__ import annotations

import argparse
import json
import shlex
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "index": "建索引：bwa index -a bwtsw <ref.fa>（生成 .bwt/.sa/.pac 族）",
    "mem": "BWA-MEM 比对（0.7.17+ 推荐；单端/双端/混合，SAM 到 stdout）",
    "aln": "BWA-backtrack 第一步：reads 比对生成 .sai（旧算法）",
    "samse": "BWA-backtrack 单端：.sai -> SAM（旧算法）",
    "sampe": "BWA-backtrack 双端：两个 .sai + R1/R2 -> SAM（旧算法）",
}


class BwaSkill(base.SkillBase):
    software = "bwa"
    binary = "bwa"

    def _resolve_bin(self, dry_run: bool = False) -> str:
        """返回 bwa 可执行路径；dry_run 时只给占位名，不探测。"""
        if dry_run:
            return self.binary
        path = base.which(self.binary)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'bwa'，请先安装：conda/mamba（bioconda::bwa=0.7.19）、"
                "brew（homebrew-core bwa）、官方源码 make 或 quay.io/biocontainers/bwa 镜像"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_bin(bool(kw.get("dry_run")))
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd: list[str] = [bin_path, subcommand]
        extra = kw.get("extra_args")
        extra_tokens = str(extra).split() if extra else []

        if subcommand == "index":
            ref = kw.get("reference") or kw.get("input")
            if not ref:
                raise ValueError("index 缺少必填参数 reference（参考序列 FASTA）")
            algo = kw.get("index_algorithm")
            if algo and algo != "auto":
                cmd += ["-a", str(algo)]
            cmd.append(str(ref))
            cmd += extra_tokens
            return cmd

        if subcommand == "mem":
            idx = kw.get("index")
            if not idx:
                raise ValueError("mem 缺少必填参数 index（BWA 索引前缀）")
            reads1 = kw.get("reads1")
            reads2 = kw.get("reads2")
            if not reads1:
                raise ValueError("mem 缺少 reads 输入（--reads1；双端加 --reads2）")
            cmd += ["-t", str(threads)]
            if kw.get("mark_split"):
                cmd.append("-M")
            if kw.get("read_group"):
                cmd += ["-R", str(kw["read_group"])]
            cmd.append(str(idx))
            cmd.append(str(reads1))
            if reads2:
                cmd.append(str(reads2))
            cmd += extra_tokens
            return cmd

        # ---- BWA-backtrack：aln / samse / sampe ----
        idx = kw.get("index")
        if not idx:
            raise ValueError(f"{subcommand} 缺少必填参数 index（BWA 索引前缀）")

        if subcommand == "aln":
            reads = kw.get("reads1")
            if not reads:
                raise ValueError("aln 缺少 reads 输入（--reads1）")
            cmd += ["-t", str(threads)]
            if kw.get("output"):
                cmd += ["-f", str(kw["output"])]
            cmd.append(str(idx))
            cmd.append(str(reads))
            cmd += extra_tokens
            return cmd

        if subcommand == "samse":
            sai = kw.get("sai")
            reads = kw.get("reads1")
            if not sai or not reads:
                raise ValueError("samse 缺少必填参数 sai / reads1")
            if kw.get("output"):
                cmd += ["-f", str(kw["output"])]
            cmd += [str(idx), str(sai), str(reads)]
            cmd += extra_tokens
            return cmd

        # sampe
        sai1 = kw.get("sai1") or kw.get("sai")
        sai2 = kw.get("sai2")
        r1 = kw.get("reads1")
        r2 = kw.get("reads2")
        if not (sai1 and sai2 and r1 and r2):
            raise ValueError("sampe 缺少必填参数 sai1 / sai2 / reads1 / reads2")
        if kw.get("output"):
            cmd += ["-f", str(kw["output"])]
        cmd += [str(idx), str(sai1), str(sai2), str(r1), str(r2)]
        cmd += extra_tokens
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（mem 默认 8 / aln 默认 4）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bwa-skill",
        description="bwa native 技能驱动（-t 线程 / TMPDIR 自动优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("reference", help="参考序列 FASTA")
    pi.add_argument("--index-algorithm", dest="index_algorithm",
                    choices=["is", "bwtsw", "auto"], default=None,
                    help="建索引算法（>2Gb 基因组用 bwtsw；默认自动）")
    _add_runtime_opts(pi)

    pm = sub.add_parser("mem", help=SUBCOMMANDS["mem"])
    pm.add_argument("--index", required=True, help="BWA 索引前缀（不含 .bwt 后缀）")
    pm.add_argument("--reads1", help="mate1 / 单端 reads（FASTQ/FASTA，可 .gz；可逗号多文件）")
    pm.add_argument("--reads2", help="mate2 reads（双端；单端省略）")
    pm.add_argument("-M", "--mark-split", action="store_true",
                    help="将更长匹配的拆分比对标为次级（Picard 兼容）")
    pm.add_argument("-R", "--read-group", help='SAM 头 @RG 行（如 "@RG\\tID:s1\\tSM:s1"）')
    pm.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pm)

    pa = sub.add_parser("aln", help=SUBCOMMANDS["aln"])
    pa.add_argument("--index", required=True, help="BWA 索引前缀")
    pa.add_argument("--reads1", help="输入 reads（FASTQ/FASTA，可 .gz）")
    pa.add_argument("--output", help=".sai 输出文件（-f；缺省 stdout）")
    _add_runtime_opts(pa)

    pse = sub.add_parser("samse", help=SUBCOMMANDS["samse"])
    pse.add_argument("--index", required=True, help="BWA 索引前缀")
    pse.add_argument("--sai", required=True, help="aln 生成的 .sai")
    pse.add_argument("--reads1", help="单端 reads")
    pse.add_argument("--output", help="SAM 输出（-f；缺省 stdout）")
    _add_runtime_opts(pse)

    ppe = sub.add_parser("sampe", help=SUBCOMMANDS["sampe"])
    ppe.add_argument("--index", required=True, help="BWA 索引前缀")
    ppe.add_argument("--sai1", help="R1 的 .sai")
    ppe.add_argument("--sai2", help="R2 的 .sai")
    ppe.add_argument("--reads1", help="R1 reads")
    ppe.add_argument("--reads2", help="R2 reads")
    ppe.add_argument("--output", help="SAM 输出（-f；缺省 stdout）")
    _add_runtime_opts(ppe)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:6s}  {v}")
        return 0
    if "--schema" in args:
        skill = BwaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BwaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "dry_run") and v is not None}
    kw["threads"] = ns.threads

    if ns.dry_run:
        try:
            cmd = skill.build_command(ns.subcommand, dry_run=True, **kw)
        except (RuntimeError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        print(shlex.join(cmd))
        return 0

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
