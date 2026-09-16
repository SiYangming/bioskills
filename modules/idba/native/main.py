#!/usr/bin/env python3
"""idba native 标准入口驱动（IDBA 1.1.3：idba_ud + fq2fa）。

IDBA (Iterative De Bruijn Graph Assembler) 的本地驱动，覆盖组装主链路：
  idba_ud  idba_ud -r <reads.fa> -o <outdir> --mink 20 --maxk 100 --step 20 [--num_threads N]
  fq2fa    fq2fa [--merge] [--filter] [--paired] <in1.fq> [in2.fq] <out.fa>

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py fq2fa --filter --merge illumina.1.fastq illumina.2.fastq illumina.fasta
   python main.py idba_ud -r illumina.fasta --mink 20 --maxk 100 --step 20 --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑对照官方文档。

⚠️ conda 版 IDBA 默认 kMaxShortSequence=128（src/sequence/short_sequence.h）；处理更长 reads
   需源码编译并改该常量（文档示例改为 160）——本驱动只做命令构造，不修改、不重编译源码。

前置：idba 已安装（conda idba=1.1.3 / quay.io/biocontainers/idba / brew brewsci/bio idba，
见 README「环境安装」）；idba_ud 自动注入线程 --num_threads。
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
    "idba_ud": "迭代 de Bruijn 图短读组装（-r reads.fa --mink --maxk --step [--num_threads]）",
    "fq2fa": "FASTQ → FASTA（支持 --filter 过滤 / --merge 合并双端 / --paired）",
}

_BINARIES = {"idba_ud": "idba_ud", "fq2fa": "fq2fa"}


class IdbaSkill(base.SkillBase):
    software = "idba"
    binary = "idba_ud"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）"
            )

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（idba_ud / fq2fa），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 IDBA 1.1.3（mamba create -n idba "
                f"-c conda-forge -c bioconda idba=1.1.3，或 quay.io/biocontainers/idba 镜像；"
                f"见 README「环境安装」）并把其加入 PATH。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """idba_ud / fq2fa：构造 IDBA 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)
        if subcommand == "idba_ud":
            return self._build_idba_ud(bin_path, **kw)
        if subcommand == "fq2fa":
            return self._build_fq2fa(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- idba_ud ----------------------------------------------------------- #
    def _build_idba_ud(self, bin_path: str, **kw) -> list[str]:
        reads = kw.get("reads") or kw.get("input")
        if not reads:
            raise RuntimeError("idba_ud 需要输入序列文件 --reads（-r，FASTA）")
        threads = self._effective_threads("idba_ud", kw.get("threads"))

        cmd: list[str] = [bin_path, "-r", str(reads)]
        if kw.get("output_dir"):
            cmd += ["-o", str(kw["output_dir"])]
        for flag, key in (("--mink", "mink"), ("--maxk", "maxk"), ("--step", "step")):
            if kw.get(key) is not None:
                cmd += [flag, str(int(kw[key]))]
        for key in ("min_contig", "min_pairs", "seed_kmer"):
            if kw.get(key) is not None:
                cmd += [f"--{key}", str(int(kw[key]))]
        for key in ("no_local", "no_correct", "pre_correction"):
            if kw.get(key):
                cmd.append(f"--{key}")
        cmd += ["--num_threads", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- fq2fa ------------------------------------------------------------- #
    def _build_fq2fa(self, bin_path: str, **kw) -> list[str]:
        inputs = kw.get("inputs") or kw.get("input")
        if isinstance(inputs, (list, tuple)):
            inputs = [str(v) for v in inputs]
        elif inputs:
            inputs = str(inputs).split()
        else:
            inputs = []
        if not inputs:
            raise RuntimeError("fq2fa 需要输入 FASTQ 文件（inputs，单端 1 个 / 双端 2 个）")

        cmd: list[str] = [bin_path]
        if kw.get("merge"):
            cmd.append("--merge")
        if kw.get("filter"):
            cmd.append("--filter")
        if kw.get("paired"):
            cmd.append("--paired")
        cmd += inputs
        if kw.get("output"):
            cmd.append(str(kw["output"]))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（fq2fa 的 stdout 由 main() 处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="idba-skill",
        description="idba native 技能驱动（idba_ud 短读组装 + fq2fa 格式转换）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # idba_ud
    pu = sub.add_parser("idba_ud", help=SUBCOMMANDS["idba_ud"])
    pu.add_argument("-r", "--reads", required=True, help="输入序列文件（FASTA）")
    pu.add_argument("-o", "--output-dir", help="输出目录（默认 out）")
    pu.add_argument("--mink", type=int, help="最小 k-mer 长度（默认 20）")
    pu.add_argument("--maxk", type=int, help="最大 k-mer 长度（默认 100）")
    pu.add_argument("--step", type=int, help="k-mer 迭代增量（默认 20）")
    pu.add_argument("--min-contig", type=int, help="contig 最小长度")
    pu.add_argument("--min-pairs", type=int, help="最少配对 read 数")
    pu.add_argument("--seed-kmer", type=int, help="比对种子 k-mer 长度")
    pu.add_argument("--no-local", action="store_true", help="关闭 local assembly")
    pu.add_argument("--no-correct", action="store_true", help="关闭纠错")
    pu.add_argument("--pre-correction", action="store_true", help="组装前先纠错")
    pu.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pu)

    # fq2fa
    pf = sub.add_parser("fq2fa", help=SUBCOMMANDS["fq2fa"])
    pf.add_argument("inputs", nargs="+", help="输入 FASTQ（单端 1 个 / 双端 2 个）")
    pf.add_argument("-o", "--output", help="输出 FASTA 文件")
    pf.add_argument("--merge", action="store_true", help="合并双端为单个 FASTA")
    pf.add_argument("--filter", action="store_true", help="过滤低质量 reads")
    pf.add_argument("--paired", action="store_true", help="按 paired 模式转换")
    pf.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pf)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（idba_ud 注入 --num_threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = IdbaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = IdbaSkill()
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
