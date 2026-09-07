#!/usr/bin/env python3
"""riboss native 标准入口驱动（RiboSS 0.46，Python 包 + 上游 CLI 生态）。

RiboSS 以 Python 包形态分发（riboss.orfs / riboss.wrapper / riboss.riboss），无独立
命令行二进制，官方推荐用法是 conda env + Jupyter/脚本调函数。本驱动把稳定函数入口封装为
原子子命令，委托同目录 run_riboss.py 执行（用当前解释器 sys.executable，确保 riboss
已装入当前环境）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py translate ATGGTCTGA
   python main.py orf_finder --annotation ann.gtf --tx tx.fa --outdir out
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

前置：riboss 环境（conda/mamba -c YangmingSi riboss=0.46 或 quay.io/bioinfortools/riboss:0.46
容器 / native/install.sh；完整流程还需 stringtie/UCSC 工具/bedtools 等，见 run_riboss.py 头注）。
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
    "translate": "基础翻译自检（riboss.orfs.translate，序列→氨基酸）",
    "orf_finder": "ORF 预测（riboss.orfs.orf_finder：注释+转录本 FASTA → ORF pkl/序列）",
    "transcriptome_assembly": "转录组参考引导组装（riboss.wrapper.transcriptome_assembly）",
}


class RibossSkill(base.SkillBase):
    software = "riboss"
    binary = "python3"  # 实际以 sys.executable 调 run_riboss.py

    def _runner(self) -> Path:
        return _HERE / "run_riboss.py"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        cmd: list[str] = [sys.executable, str(self._runner()), subcommand]

        if subcommand == "translate":
            seq = kw.get("seq")
            if not seq:
                raise RuntimeError("translate 需要 seq 参数（核酸序列）")
            cmd.append(str(seq))

        elif subcommand == "orf_finder":
            for key, flag in (("annotation", "--annotation"), ("tx", "--tx")):
                v = kw.get(key)
                if not v:
                    raise RuntimeError(f"orf_finder 需要 {key} 参数")
                cmd += [flag, str(v)]
            if kw.get("outdir"):
                cmd += ["--outdir", str(kw["outdir"])]
            if kw.get("ncrna"):
                cmd.append("--ncrna")
            if kw.get("start_codons"):
                cmd += ["--start-codons", str(kw["start_codons"])]

        elif subcommand == "transcriptome_assembly":
            for key, flag in (("superkingdom", "--superkingdom"), ("genome", "--genome"),
                              ("long_reads", "--long-reads")):
                v = kw.get(key)
                if not v:
                    raise RuntimeError(f"transcriptome_assembly 需要 {key} 参数")
                cmd += [flag, str(v)]
            if kw.get("short_reads"):
                cmd += ["--short-reads", str(kw["short_reads"])]
            if kw.get("strandness"):
                cmd += ["--strandness", str(kw["strandness"])]
            if kw.get("annotation"):
                cmd += ["--annotation", str(kw["annotation"])]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--threads", str(threads)]
            if kw.get("outdir"):
                cmd += ["--outdir", str(kw["outdir"])]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="riboss-skill",
        description="RiboSS native 技能驱动（run_riboss.py 委托）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pt = sub.add_parser("translate", help=SUBCOMMANDS["translate"])
    pt.add_argument("seq", help="核酸序列（如 ATGGTCTGA → MV）")
    _add_runtime_opts(pt)

    po = sub.add_parser("orf_finder", help=SUBCOMMANDS["orf_finder"])
    po.add_argument("--annotation", required=True, help="基因注释 GTF/GFF3/BED/genePred")
    po.add_argument("--tx", required=True, help="转录本 FASTA")
    po.add_argument("--outdir", default=".", help="输出目录（默认 .）")
    po.add_argument("--ncrna", action="store_true", help="不移除非编码 RNA 转录本")
    po.add_argument("--start-codons", default=None,
                    help="起始密码子列表，逗号分隔（默认 ATG,CTG,GTG,TTG）")
    _add_runtime_opts(po)

    pa = sub.add_parser("transcriptome_assembly", help=SUBCOMMANDS["transcriptome_assembly"])
    pa.add_argument("--superkingdom", required=True, choices=["Archaea", "Bacteria", "Eukaryota"])
    pa.add_argument("--genome", required=True, help="基因组 FASTA")
    pa.add_argument("--long-reads", required=True, help="长读比对 BAM（PacBio/ONT）")
    pa.add_argument("--short-reads", help="短读比对 BAM（Illumina，混合组装）")
    pa.add_argument("--strandness", choices=["rf", "fr"], help="链特异性（--short-reads 时需要）")
    pa.add_argument("--annotation", help="参考注释 GTF（可选）")
    pa.add_argument("--outdir", default=".", help="输出目录（默认 .）")
    _add_runtime_opts(pa)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="线程数（覆盖默认；assembly 透传 StringTie -p）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:24s} {v}")
        return 0
    if "--schema" in args:
        skill = RibossSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RibossSkill()
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
