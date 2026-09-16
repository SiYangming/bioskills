#!/usr/bin/env python3
"""geta（GETA 自动化基因预测流程，chenlianfu）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py geta --RM_species fungi --genome genome.fasta -1 reads.1.fastq -2 reads.2.fastq \
       --protein homolog.fasta --use_existed_augustus_species malassezia_sympodialis \
       --RM_lib consensi.fa --pfam_db Pfam-AB.hmm --gene_prefix MS01Gene --threads 8
   python main.py best_models out.gff3 -o bestGeneModels.gff3
   python main.py gff3_to_gtf genome.fasta bestGeneModels.gff3 -o bestGeneModels.gtf
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  geta          geta.pl --RM_species <s> --genome <genome> [-1 <r1>] [-2 <r2>] [--protein <faa>] \
                    [--use_existed_augustus_species <name>] [--RM_lib <lib>] --cpu N \
                    [--pfam_db <hmm>] [--gene_prefix <p>]
  best_models   bestGeneModels.pl <out.gff3>          （结果写 stdout；给出 -o 时由本驱动落盘）
  gff3_to_gtf   gff3ToGtf.pl <genome.fasta> <bestGeneModels.gff3>（结果写 stdout；-o 时落盘）
geta 为 Perl 驱动：本驱动经 PATH 解析 geta.pl（可用 conda/容器/官方 tarball 安装，见 README）。
"""

from __future__ import annotations

import argparse
import json
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
    "geta": "geta.pl：一站式自动基因预测（RepeatMasker + AUGUSTUS/同源 + 整合）",
    "best_models": "bestGeneModels.pl：去除可变剪接，保留最优基因模型（结果写 stdout）",
    "gff3_to_gtf": "gff3ToGtf.pl：把 GFF3 转换为 GTF（结果写 stdout）",
}

# 子命令 -> 实际可执行脚本名（GETA 安装 bin/ 下）
BINARY_FOR = {
    "geta": "geta.pl",
    "best_models": "bestGeneModels.pl",
    "gff3_to_gtf": "gff3ToGtf.pl",
}


class GetaSkill(base.SkillBase):
    software = "geta"
    binary = "geta.pl"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式：软件级 meta.yaml 位于 modules/geta/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行脚本（geta.pl / bestGeneModels.pl / gff3ToGtf.pl）。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（官方 tarball github.com/chenlianfu/geta 解压后 bin/ 加入 PATH）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 GETA 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "geta":
            binary = self._resolve_tool(BINARY_FOR["geta"])
            genome = kw.get("genome")
            if not genome:
                raise ValueError("geta 缺少必填参数 genome（--genome 基因组 FASTA）")
            cmd: list[str] = [binary]
            if kw.get("rm_species"):
                cmd += ["--RM_species", str(kw["rm_species"])]
            cmd += ["--genome", str(genome)]
            if kw.get("reads1"):
                cmd += ["-1", str(kw["reads1"])]
            if kw.get("reads2"):
                cmd += ["-2", str(kw["reads2"])]
            if kw.get("protein"):
                cmd += ["--protein", str(kw["protein"])]
            if kw.get("augustus_species"):
                cmd += ["--use_existed_augustus_species", str(kw["augustus_species"])]
            if kw.get("rm_lib"):
                cmd += ["--RM_lib", str(kw["rm_lib"])]
            cmd += ["--cpu", str(threads)]
            if kw.get("pfam_db"):
                cmd += ["--pfam_db", str(kw["pfam_db"])]
            if kw.get("gene_prefix"):
                cmd += ["--gene_prefix", str(kw["gene_prefix"])]

        elif subcommand == "best_models":
            binary = self._resolve_tool(BINARY_FOR["best_models"])
            gff3 = kw.get("gff3")
            if not gff3:
                raise ValueError("best_models 缺少必填参数 gff3（GETA 输出的 out.gff3）")
            cmd = [binary, str(gff3)]

        else:  # gff3_to_gtf
            binary = self._resolve_tool(BINARY_FOR["gff3_to_gtf"])
            genome = kw.get("genome")
            gff3 = kw.get("gff3")
            if not genome:
                raise ValueError("gff3_to_gtf 缺少必填参数 genome（genome.fasta）")
            if not gff3:
                raise ValueError("gff3_to_gtf 缺少必填参数 gff3（bestGeneModels.gff3）")
            cmd = [binary, str(genome), str(gff3)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="geta-skill",
        description="geta（GETA）native 技能驱动（自动线程/临时目录优化；一站式自动基因预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # geta
    pg = sub.add_parser("geta", help=SUBCOMMANDS["geta"])
    pg.add_argument("--genome", required=True, help="基因组 FASTA（--genome）")
    pg.add_argument("--RM_species", dest="rm_species", help="RepeatMasker 物种类型（--RM_species，教学示例 fungi）")
    pg.add_argument("-1", "--reads1", dest="reads1", help="RNA-seq 正向 reads（-1）")
    pg.add_argument("-2", "--reads2", dest="reads2", help="RNA-seq 反向 reads（-2）")
    pg.add_argument("--protein", help="同源蛋白序列文件（--protein）")
    pg.add_argument("--use_existed_augustus_species", dest="augustus_species",
                    help="已训练好的 AUGUSTUS 物种参数（--use_existed_augustus_species）")
    pg.add_argument("--RM_lib", dest="rm_lib", help="重复序列数据库（--RM_lib）")
    pg.add_argument("--pfam_db", dest="pfam_db", help="Pfam 数据库路径（--pfam_db）")
    pg.add_argument("--gene_prefix", dest="gene_prefix", help="基因 ID 前缀（--gene_prefix）")
    pg.add_argument("--extra-args", dest="extra_args", help="透传给 geta.pl 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pg)

    # best_models
    pb = sub.add_parser("best_models", help=SUBCOMMANDS["best_models"])
    pb.add_argument("gff3", help="GETA 输出的 out.gff3")
    pb.add_argument("-o", "--output", help="输出 bestGeneModels.gff3（脚本写 stdout，驱动捕获落盘）")
    pb.add_argument("--extra-args", dest="extra_args", help="透传给 bestGeneModels.pl 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    # gff3_to_gtf
    pt = sub.add_parser("gff3_to_gtf", help=SUBCOMMANDS["gff3_to_gtf"])
    pt.add_argument("genome", help="基因组 FASTA（genome.fasta）")
    pt.add_argument("gff3", help="bestGeneModels.gff3")
    pt.add_argument("-o", "--output", help="输出 bestGeneModels.gtf（脚本写 stdout，驱动捕获落盘）")
    pt.add_argument("--extra-args", dest="extra_args", help="透传给 gff3ToGtf.pl 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pt)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（geta 注入 --cpu N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = GetaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GetaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # best_models / gff3_to_gtf 写 stdout；给出 --output 时落盘
    if ns.subcommand in ("best_models", "gff3_to_gtf") and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stdout and not getattr(ns, "output", None):
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
