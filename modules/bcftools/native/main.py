#!/usr/bin/env python3
"""bcftools native 标准入口驱动。

bcftools（samtools 家族，C 程序）CLI 形如：
    bcftools view [-O b|u|z|v] [-i EXPR] [-s SAMPLES] [-r REGION] file.vcf.gz
    bcftools mpileup -f ref.fa a.bam b.bam
    bcftools call -m -v [-O z] [-o out.vcf.gz] in.bcf
    bcftools sort [-T PREFIX] [-o out.vcf.gz] in.vcf.gz
    bcftools index [-t] in.vcf.gz
    bcftools norm -f ref.fa -m -any in.vcf.gz
    bcftools query -f '%CHROM\\t%POS\\n' in.vcf.gz
    bcftools consensus -f ref.fa -H 1 in.vcf.gz
conda / brew / biocontainer 提供同一 `bcftools` 可执行名。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py view raw.bcf -O z -o out.vcf.gz -i 'QUAL>30'
   python main.py mpileup -f ref.fa a.bam b.bam -O b -o raw.bcf
   python main.py call raw.bcf -m -v -O z -o calls.vcf.gz
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位 bcftools：PATH 上 `bcftools`（bioconda / brew / 官方 make 产物均可）。
- sort 自动注入 -T 临时前缀（self.tmpdir）；TMPDIR 经 env 注入。
- bcftools 多线程支持分散（部分子命令支持 --threads），本驱动不自动注入，
  需用时经 --extra-args 透传（如 --extra-args '--threads 4'）。
- --dry-run 仅构造并打印 argv（不执行），供降级 argv 构造回归。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "view": "VCF/BCF 查看、格式转换与子集/表达式过滤（-i/-e/-s/-r）",
    "mpileup": "多 BAM → 位点 pileup → BCF/VCF（-f 参考）",
    "call": "变异检测与基因型判定（-m 多等位模型 / -c 旧 consensus 模型）",
    "sort": "按坐标排序 VCF/BCF（自动注入 -T 临时前缀）",
    "index": "建立索引（默认 .csi；-t 生成 .tbi）",
    "norm": "左对齐归一化 + 拆分多等位（-f 参考 / -m 模式）",
    "query": "灵活格式提取（-f 格式串 / -l 样本清单）",
    "consensus": "由 VCF + 参考生成一致性序列（-H 单倍型）",
}


class BcftoolsSkill(base.SkillBase):
    software = "bcftools"
    binary = "bcftools"

    def _resolve_bin(self, dry_run: bool = False) -> str:
        if dry_run:
            return self.binary
        path = base.which(self.binary)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'bcftools'，请先安装：conda/mamba（bioconda::bcftools=1.24）、"
                "brew（homebrew-core bcftools）、官方源码 configure/make 或 "
                "quay.io/biocontainers/bcftools 镜像"
            )
        return path

    def _add_output_type(self, cmd: list[str], kw: dict) -> None:
        ot = kw.get("output_type")
        if ot:
            cmd += ["-O", str(ot)]
        out = kw.get("output")
        if out:
            cmd += ["-o", str(out)]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_bin(bool(kw.get("dry_run")))
        cmd: list[str] = [bin_path, subcommand]
        extra = kw.get("extra_args")
        extra_tokens = str(extra).split() if extra else []

        if subcommand == "view":
            inp = kw.get("input")
            if not inp:
                raise ValueError("view 缺少必填参数 input（VCF/BCF 文件）")
            for flag, key in [("-i", "include"), ("-e", "exclude"),
                              ("-s", "sample"), ("-r", "region")]:
                if kw.get(key):
                    cmd += [flag, str(kw[key])]
            self._add_output_type(cmd, kw)
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        if subcommand == "mpileup":
            bams = kw.get("bams") or kw.get("input")
            if not bams:
                raise ValueError("mpileup 缺少 BAM 输入（positional bams）")
            fasta = kw.get("fasta")
            if not fasta:
                raise ValueError("mpileup 缺少必填参数 fasta（-f 参考序列）")
            cmd += ["-f", str(fasta)]
            self._add_output_type(cmd, kw)
            cmd += extra_tokens
            if isinstance(bams, list):
                cmd += [str(b) for b in bams]
            else:
                cmd.append(str(bams))
            return cmd

        if subcommand == "call":
            inp = kw.get("input")
            if not inp:
                raise ValueError("call 缺少必填参数 input（mpileup 的 BCF/VCF）")
            if kw.get("consensus"):
                cmd.append("-c")
            else:
                cmd.append("-m")
            if kw.get("variants_only"):
                cmd.append("-v")
            if kw.get("fasta"):
                cmd += ["-f", str(kw["fasta"])]
            self._add_output_type(cmd, kw)
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        if subcommand == "sort":
            inp = kw.get("input")
            if not inp:
                raise ValueError("sort 缺少必填参数 input")
            cmd += ["-T", os.path.join(self.tmpdir, f"bcftools_sort.{os.getpid()}")]
            self._add_output_type(cmd, kw)
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        if subcommand == "index":
            inp = kw.get("input")
            if not inp:
                raise ValueError("index 缺少必填参数 input")
            if kw.get("index_type") == "tbi" or kw.get("tbi"):
                cmd.append("-t")
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        if subcommand == "norm":
            inp = kw.get("input")
            if not inp:
                raise ValueError("norm 缺少必填参数 input")
            fasta = kw.get("fasta")
            if not fasta:
                raise ValueError("norm 缺少必填参数 fasta（-f 参考，左对齐必需）")
            cmd += ["-f", str(fasta)]
            if kw.get("multiallelic"):
                mode = str(kw["multiallelic"])
                # 规范化为 bcftools 真实写法：any -> -any
                if not mode.startswith("-") and not mode.startswith("+"):
                    mode = "-" + mode
                cmd += ["-m", mode]
            self._add_output_type(cmd, kw)
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        if subcommand == "query":
            inp = kw.get("input")
            if not inp:
                raise ValueError("query 缺少必填参数 input")
            if kw.get("list_samples"):
                cmd.append("-l")
            else:
                fmt = kw.get("format")
                if not fmt:
                    raise ValueError("query 需要 -f 格式串或 -l/--list-samples")
                cmd += ["-f", str(fmt)]
                if kw.get("sample"):
                    cmd += ["-s", str(kw["sample"])]
                if kw.get("region"):
                    cmd += ["-r", str(kw["region"])]
            cmd += extra_tokens
            cmd.append(str(inp))
            return cmd

        # consensus
        inp = kw.get("input")
        if not inp:
            raise ValueError("consensus 缺少必填参数 input")
        fasta = kw.get("fasta")
        if not fasta:
            raise ValueError("consensus 缺少必填参数 fasta（-f 参考）")
        cmd += ["-f", str(fasta)]
        if kw.get("haplotype") is not None:
            cmd += ["-H", str(kw["haplotype"])]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        cmd += extra_tokens
        cmd.append(str(inp))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="线程提示（bcftools 子命令线程支持不一；必要时用 --extra-args 透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")


def _add_output_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("-O", "--output-type", dest="output_type",
                   choices=["b", "u", "z", "v"], help="输出类型 b|u|z|v（BCF/gzip VCF/…）")
    p.add_argument("-o", "--output", help="输出文件（缺省 stdout）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bcftools-skill",
        description="bcftools native 技能驱动（变异检测/后处理；-T 临时前缀 / TMPDIR 自动优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pv = sub.add_parser("view", help=SUBCOMMANDS["view"])
    pv.add_argument("input", help="VCF/BCF 文件")
    pv.add_argument("-i", "--include", help="包含表达式（如 'QUAL>30 && INFO/DP>10'）")
    pv.add_argument("-e", "--exclude", help="排除表达式")
    pv.add_argument("-s", "--sample", help="样本子集")
    pv.add_argument("-r", "--region", help="区域（如 chr1:1000-2000）")
    _add_output_opts(pv)
    _add_runtime_opts(pv)

    pm = sub.add_parser("mpileup", help=SUBCOMMANDS["mpileup"])
    pm.add_argument("bams", nargs="+", help="比对 BAM 文件（可多个）")
    pm.add_argument("-f", "--fasta", required=True, help="参考序列 FASTA")
    _add_output_opts(pm)
    _add_runtime_opts(pm)

    pc = sub.add_parser("call", help=SUBCOMMANDS["call"])
    pc.add_argument("input", help="mpileup 输出的 BCF/VCF")
    pc.add_argument("-m", "--multiallelic", action="store_true", help="多等位基因 caller 模型（默认）")
    pc.add_argument("-c", "--consensus", action="store_true", help="旧 consensus 模型（慎用）")
    pc.add_argument("-v", "--variants-only", action="store_true", dest="variants_only", help="仅输出变异位点")
    pc.add_argument("-f", "--fasta", help="参考序列 FASTA（可选）")
    _add_output_opts(pc)
    _add_runtime_opts(pc)

    ps = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    ps.add_argument("input", help="VCF/BCF 文件")
    _add_output_opts(ps)
    _add_runtime_opts(ps)

    pidx = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pidx.add_argument("input", help="VCF/BCF 文件")
    pidx.add_argument("-t", "--tbi", action="store_true", help="生成 .tbi（默认 .csi）")
    pidx.add_argument("--index-type", dest="index_type", choices=["csi", "tbi"], default=None,
                      help="索引类型（等价 -t）")
    _add_runtime_opts(pidx)

    pn = sub.add_parser("norm", help=SUBCOMMANDS["norm"])
    pn.add_argument("input", help="VCF/BCF 文件")
    pn.add_argument("-f", "--fasta", required=True, help="参考序列 FASTA（左对齐必需）")
    pn.add_argument("-m", "--multiallelic", help="拆分模式：-any/-snps/-indels/+any …")
    _add_output_opts(pn)
    _add_runtime_opts(pn)

    pq = sub.add_parser("query", help=SUBCOMMANDS["query"])
    pq.add_argument("input", help="VCF/BCF 文件")
    pq.add_argument("-f", "--format", help='格式串（如 "%CHROM\\t%POS\\t%REF\\t%ALT\\n"）')
    pq.add_argument("-l", "--list-samples", action="store_true", dest="list_samples", help="列出样本名")
    pq.add_argument("-s", "--sample", help="样本子集")
    pq.add_argument("-r", "--region", help="区域")
    _add_runtime_opts(pq)

    pcs = sub.add_parser("consensus", help=SUBCOMMANDS["consensus"])
    pcs.add_argument("input", help="VCF/BCF 文件")
    pcs.add_argument("-f", "--fasta", required=True, help="参考序列 FASTA")
    pcs.add_argument("-H", "--haplotype", type=int, help="单倍型 1 或 2")
    pcs.add_argument("-o", "--output", help="输出 FASTA（缺省 stdout）")
    _add_runtime_opts(pcs)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s}  {v}")
        return 0
    if "--schema" in args:
        skill = BcftoolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BcftoolsSkill()
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
