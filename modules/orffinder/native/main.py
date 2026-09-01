#!/usr/bin/env python3
"""orffinder native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -in transcripts.fa -out out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/flrnaseq.smk/workflow/scripts/orffinder.py：
  ORFfinder -in <fasta> -out <file> -outfmt <int> {extra} -logfile <log>
flrnaseq 默认参数（config.yaml orffinder 段）：
  outfmt: 2（Text ASN.1；suffix_map: 0=_orf.fa, 1=_cds.fa, 2=.asn1, 3=.ft）
  extra_params: "-s 2 -ml 30"
本驱动把 extra 拆为结构化参数（start_codon/min_length/genetic_code/strand/ignore_nested），
仍保留 extra_args 透传。ORFfinder 为单线程工具，线程数仅作调度参考。
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import shutil
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
    "run": "运行 NCBI ORFfinder 预测 ORF（-in/-out/-outfmt/-g/-s/-ml/-strand/-n）",
}

BIN = "ORFfinder"

# flrnaseq config.yaml orffinder 段：outfmt -> 输出后缀映射
SUFFIX_MAP = {0: "_orf.fa", 1: "_cds.fa", 2: ".asn1", 3: ".ft"}


class OrffinderSkill(base.SkillBase):
    software = "orffinder"
    binary = BIN

    def _resolve_bin(self) -> str:
        """解析 ORFfinder 路径（找不到抛错）。"""
        path = base.which(BIN)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{BIN}'，请先通过 Conda/Docker/Apptainer 安装 orffinder。"
            )
        return path

    @staticmethod
    def _maybe_decompress(fasta: str, tmpdir: str) -> str:
        """输入为 .gz 时解压到 tmpdir 并返回解压路径（迁移自原脚本 gunzip 逻辑）。"""
        if fasta.endswith(".gz"):
            out = os.path.join(tmpdir, os.path.basename(fasta)[:-3])
            with gzip.open(fasta, "rt") as fh_in, open(out, "w", encoding="utf-8") as fh_out:
                shutil.copyfileobj(fh_in, fh_out)
            return out
        return fasta

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 ORFfinder 命令行。"""
        if subcommand != "run":
            raise ValueError(f"未知子命令: {subcommand}")

        fasta = kw.get("input") or kw.get("fasta")
        if not fasta:
            raise ValueError("缺少必填参数 input（输入核酸 FASTA）")

        tmpdir = self.make_tmpdir("orffinder_")
        input_fa = self._maybe_decompress(str(fasta), tmpdir)

        # 输出路径：显式 output > <input_stem><suffix>
        output = kw.get("output")
        if not output:
            outfmt = int(kw.get("outfmt", 2))
            suffix = SUFFIX_MAP.get(outfmt, ".asn1")
            stem = Path(str(fasta)).name
            for gz_suffix in (".gz",):
                if stem.endswith(gz_suffix):
                    stem = stem[: -len(gz_suffix)]
            stem = os.path.splitext(stem)[0]
            output = os.path.join(str(Path(str(fasta)).parent), f"{stem}{suffix}")
        os.makedirs(os.path.dirname(output) or ".", exist_ok=True)

        binary = self._resolve_bin()
        cmd: list[str] = [binary, "-in", input_fa, "-out", str(output)]

        # outfmt（默认 2，来自 flrnaseq config）
        cmd += ["-outfmt", str(kw.get("outfmt", 2))]

        # 结构化参数
        if kw.get("genetic_code") is not None:
            cmd += ["-g", str(kw["genetic_code"])]
        if kw.get("start_codon") is not None:
            cmd += ["-s", str(kw["start_codon"])]
        if kw.get("min_length") is not None:
            cmd += ["-ml", str(kw["min_length"])]
        if kw.get("strand"):
            cmd += ["-strand", str(kw["strand"])]
        if kw.get("ignore_nested"):
            cmd += ["-n", "true"]

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
        prog="orffinder-skill",
        description="orffinder (NCBI ORFfinder) native 技能驱动（自动临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-in", "--input", required=True, help="输入核酸 FASTA")
    pr.add_argument("-out", "--output", help="输出文件（默认 <input_stem><suffix>）")
    pr.add_argument("-outfmt", "--outfmt", type=int, default=2,
                    help="输出格式：0=ORFs FASTA, 1=CDS FASTA, 2=Text ASN.1, 3=Feature table（默认 2）")
    pr.add_argument("-g", "--genetic-code", type=int, help="遗传密码（1-31）")
    pr.add_argument("-s", "--start-codon", type=int,
                    help="起始密码子：0=仅 ATG, 1=ATG 与替代, 2=任意有义密码子（默认 2）")
    pr.add_argument("-ml", "--min-length", type=int, help="最小 ORF 长度 nt（默认 30）")
    pr.add_argument("-strand", "--strand", choices=["both", "plus", "minus"], help="链方向")
    pr.add_argument("-n", "--ignore-nested", action="store_true", help="忽略嵌套 ORF")
    pr.add_argument("--extra-args", help="透传给 ORFfinder 的额外参数")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（ORFfinder 单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = OrffinderSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OrffinderSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
