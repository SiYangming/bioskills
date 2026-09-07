#!/usr/bin/env python3
"""riborf native 标准入口驱动（RibORF 2.0，perl 子脚本管线）。

RibORF 2.0 以 perl 子脚本分发（无单一主程序），本驱动按流水线子命令逐条
调用 `perl <script>.pl`，脚本路径按 PATH / $RIBORF_HOME 解析（conda 包与
自建 Docker 镜像均会把 RibORF.2.0/*.pl 暴露到 PATH）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py remove_adapter -f reads.fastq -a CTGTAGGCAC -o trimmed.fastq
   python main.py orfannotate -g genome.fa -t ref.genePred -o orf_out
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

前置：perl + 脚本可执行（conda/mamba 或 quay.io/bioinfortools/riborf 容器 /
native/install.sh；bowtie2/tophat/R 等在完整 Ribo-seq 流程时才需要）。
"""

from __future__ import annotations

import argparse
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

# 子命令 -> (perl 脚本名, 说明)
SUBCOMMANDS = {
    "remove_adapter": ("removeAdapter.pl", "去除 3' 接头并过滤短 read（-f fastq -a adapter -o out）"),
    "orfannotate": ("ORFannotate.pl", "从转录本 genePred 注释候选 ORF（-g genome -t genePred -o dir）"),
    "read_dist": ("readDist.pl", "检查 RPF 5' 端在起止密码子附近分布（周期性质控）"),
    "offset_correct": ("offsetCorrect.pl", "按 offset 参数校正 read 位置（-r sam -p params -o out）"),
    "riborf": ("ribORF.pl", "用校正后 read 预测候选 ORF 的翻译概率（SVM/logistic）"),
    "merge_orf": ("mergeORF.pl", "合并多次预测的重叠 ORF（-c 用 ~ 分隔多文件）"),
}

# 各脚本脚本名与解析器要求（用于 --list-commands / 自省提示）
SCRIPT_NAMES = {k: v[0] for k, v in SUBCOMMANDS.items()}


class RiborfSkill(base.SkillBase):
    software = "riborf"
    binary = "perl"

    def _resolve_script(self, subcommand: str) -> str:
        """按 PATH / $RIBORF_HOME 定位 perl 脚本（conda 包与镜像均装到 PATH）。"""
        script = SCRIPT_NAMES[subcommand]
        found = shutil.which(script)
        if not found:
            home = os.environ.get("RIBORF_HOME")
            if home:
                cand = Path(home) / script
                if cand.exists():
                    found = str(cand)
        if not found:
            raise RuntimeError(
                f"未找到 perl 脚本 '{script}'（PATH / $RIBORF_HOME 均无）。"
                "请先安装 RibORF 2.0：conda/mamba -c YangmingSi riborf、"
                "quay.io/bioinfortools/riborf 容器或 bash native/install.sh"
            )
        return found

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        perl = self._resolve_binary()
        script = self._resolve_script(subcommand)
        cmd: list[str] = [perl, script]

        def push(flag: str, key: str) -> None:
            v = kw.get(key)
            if v:
                cmd.extend([flag, str(v)])

        # removeAdapter.pl: -f fastq -a adapter -o output [-l minlen]
        if subcommand == "remove_adapter":
            push("-f", "fastq"); push("-a", "adapter"); push("-o", "output")
            push("-l", "min_length")
        # ORFannotate.pl: -g genome -t genePred -o outdir [-s startcodons] [-l len]
        elif subcommand == "orfannotate":
            push("-g", "genome"); push("-t", "genepred"); push("-o", "output")
            push("-s", "start_codons"); push("-l", "orf_min_length")
        # readDist.pl: -f sam -g genePred -o outdir [-d lens] [-l left] [-r right]
        elif subcommand == "read_dist":
            push("-f", "input_sam"); push("-g", "genepred"); push("-o", "output")
            push("-d", "read_lengths"); push("-l", "left_flank"); push("-r", "right_flank")
        # offsetCorrect.pl: -r sam -p params -o output
        elif subcommand == "offset_correct":
            push("-r", "input_sam"); push("-p", "offset_params"); push("-o", "output")
        # ribORF.pl: -f sam -c orfGenepred -o outdir [-l len] [-r reads] [-p pvalue]
        elif subcommand == "riborf":
            push("-f", "input_sam"); push("-c", "candidate_orf"); push("-o", "output")
            push("-l", "orf_min_length"); push("-r", "orf_read_cutoff")
            push("-p", "predict_pvalue_cutoff")
        # mergeORF.pl: -f sam -c predicted(~分隔) -o outdir
        elif subcommand == "merge_orf":
            push("-f", "input_sam"); push("-c", "predicted_orfs"); push("-o", "output")

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="riborf-skill",
        description="RibORF 2.0 native 技能驱动（perl 子脚本管线）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("remove_adapter", help=SUBCOMMANDS["remove_adapter"][1])
    pa.add_argument("-f", "--fastq", required=True); pa.add_argument("-a", "--adapter", required=True)
    pa.add_argument("-o", "--output", required=True); pa.add_argument("-l", "--min-length", type=int)
    _add_runtime_opts(pa)

    po = sub.add_parser("orfannotate", help=SUBCOMMANDS["orfannotate"][1])
    po.add_argument("-g", "--genome", required=True); po.add_argument("-t", "--genepred", required=True)
    po.add_argument("-o", "--output", required=True)
    po.add_argument("-s", "--start-codons", help="起始密码子集合，/ 分隔（默认 ATG/CTG/GTG/TTG/ACG）")
    po.add_argument("-l", "--orf-min-length", type=int, help="最小候选 ORF 长度 nt（默认 6）")
    _add_runtime_opts(po)

    prd = sub.add_parser("read_dist", help=SUBCOMMANDS["read_dist"][1])
    prd.add_argument("-f", "--input-sam", required=True); prd.add_argument("-g", "--genepred", required=True)
    prd.add_argument("-o", "--output", required=True)
    prd.add_argument("-d", "--read-lengths", help="RPF 长度，逗号分隔（默认 25..34）")
    prd.add_argument("-l", "--left-flank", type=int); prd.add_argument("-r", "--right-flank", type=int)
    _add_runtime_opts(prd)

    poc = sub.add_parser("offset_correct", help=SUBCOMMANDS["offset_correct"][1])
    poc.add_argument("-r", "--input-sam", required=True); poc.add_argument("-p", "--offset-params", required=True)
    poc.add_argument("-o", "--output", required=True)
    _add_runtime_opts(poc)

    pr = sub.add_parser("riborf", help=SUBCOMMANDS["riborf"][1])
    pr.add_argument("-f", "--input-sam", required=True); pr.add_argument("-c", "--candidate-orf", required=True)
    pr.add_argument("-o", "--output", required=True)
    pr.add_argument("-l", "--orf-min-length", type=int); pr.add_argument("-r", "--orf-read-cutoff", type=int)
    pr.add_argument("-p", "--predict-pvalue-cutoff", type=float)
    _add_runtime_opts(pr)

    pm = sub.add_parser("merge_orf", help=SUBCOMMANDS["merge_orf"][1])
    pm.add_argument("-f", "--input-sam", required=True)
    pm.add_argument("-c", "--predicted-orfs", required=True, help="预测 ORF genePred 文件，多文件用 ~ 分隔")
    pm.add_argument("-o", "--output", required=True)
    _add_runtime_opts(pm)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="预留：perl 子脚本多为单线程")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, (script, desc) in SUBCOMMANDS.items():
            print(f"{k:16s} [{script}] {desc}")
        return 0
    if "--schema" in args:
        skill = RiborfSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RiborfSkill()
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

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
