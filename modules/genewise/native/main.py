#!/usr/bin/env python3
"""genewise（GeneWise / wise2）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py genewise -gff homolog.fasta genome_region.fasta -o gene.gff
   python main.py homolog --coverage_ratio 0.4 --evalue 1e-9 --max_gene_length 2000 --threads 8 homolog.fasta genome.fasta
   python main.py gff2gff3 --genome genome.fasta --min_score 15 --gene_prefix genewise genewise.gff -o genewise.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  genewise   genewise [-gff] <protein> <dna>
  homolog    homolog_genewise --cpu N [--coverage_ratio R] [--evalue E] [--max_gene_length L] <protein.fasta> <genome.fasta>
  gff2gff3   homolog_genewiseGFF2GFF3 --genome <genome> [--min_score S] [--gene_prefix P] <genewise.gff>
             （结果写 stdout；给出 -o 时由本驱动捕获落盘为 GFF3）
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
    "genewise": "genewise 单条同源蛋白→DNA 基因结构预测（-gff 输出 GFF）",
    "homolog": "homolog_genewise 全基因组并行同源蛋白预测（--cpu/--coverage_ratio/--evalue/--max_gene_length）",
    "gff2gff3": "homolog_genewiseGFF2GFF3 把 genewise GFF 转 GFF3 并按 --min_score 过滤",
}

# 子命令 -> 实际可执行文件名（wise2 安装 bin/ 下的脚本）
BINARY_FOR = {
    "genewise": "genewise",
    "homolog": "homolog_genewise",
    "gff2gff3": "homolog_genewiseGFF2GFF3",
}


class GenewiseSkill(base.SkillBase):
    software = "genewise"
    binary = "genewise"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式：软件级 meta.yaml 位于 modules/genewise/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（genewise / homolog_genewise / homolog_genewiseGFF2GFF3）。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda wise2=2.4.1，或官方源码 wise2.4.1 编译后 bin/ 加入 PATH）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 genewise / 封装脚本命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "genewise":
            binary = self._resolve_tool(BINARY_FOR["genewise"])
            protein = kw.get("protein")
            dna = kw.get("dna")
            if not protein:
                raise ValueError("genewise 缺少必填参数 protein（同源蛋白 FASTA）")
            if not dna:
                raise ValueError("genewise 缺少必填参数 dna（目标 DNA 序列）")
            cmd: list[str] = [binary]
            if kw.get("gff"):
                cmd.append("-gff")
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            # 官方用法：genewise [options] <protein> <dna>
            cmd += [str(protein), str(dna)]
            return cmd

        if subcommand == "homolog":
            binary = self._resolve_tool(BINARY_FOR["homolog"])
            protein = kw.get("protein")
            dna = kw.get("dna")
            if not protein:
                raise ValueError("homolog 缺少必填参数 protein（同源蛋白 FASTA）")
            if not dna:
                raise ValueError("homolog 缺少必填参数 dna（基因组 FASTA）")
            cmd = [binary, "--cpu", str(threads)]
            if kw.get("coverage_ratio") is not None:
                cmd += ["--coverage_ratio", str(kw["coverage_ratio"])]
            if kw.get("evalue") is not None:
                cmd += ["--evalue", str(kw["evalue"])]
            if kw.get("max_gene_length") is not None:
                cmd += ["--max_gene_length", str(kw["max_gene_length"])]
            cmd += [str(protein), str(dna)]
        else:  # gff2gff3
            binary = self._resolve_tool(BINARY_FOR["gff2gff3"])
            gff = kw.get("gff")
            if not gff:
                raise ValueError("gff2gff3 缺少必填参数 gff（genewise GFF，位置参数）")
            cmd = [binary]
            if kw.get("genome"):
                cmd += ["--genome", str(kw["genome"])]
            if kw.get("min_score") is not None:
                cmd += ["--min_score", str(kw["min_score"])]
            if kw.get("gene_prefix"):
                cmd += ["--gene_prefix", str(kw["gene_prefix"])]
            cmd += [str(gff)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genewise-skill",
        description="genewise（GeneWise / wise2）native 技能驱动（自动线程/临时目录优化；同源蛋白辅助基因预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # genewise [options] <protein> <dna>
    pg = sub.add_parser("genewise", help=SUBCOMMANDS["genewise"])
    pg.add_argument("protein", help="查询同源蛋白 FASTA（官方位置参数 <protein>）")
    pg.add_argument("dna", help="目标 DNA 序列（官方位置参数 <dna>）")
    pg.add_argument("-gff", dest="gff", action="store_true", help="以 GFF 格式输出预测结果（-gff）")
    pg.add_argument("-o", "--output", help="输出文件（genewise 写 stdout，驱动捕获落盘）")
    pg.add_argument("--extra-args", dest="extra_args", help="透传给 genewise 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pg)

    # homolog_genewise [options] <protein.fasta> <genome.fasta>
    ph = sub.add_parser("homolog", help=SUBCOMMANDS["homolog"])
    ph.add_argument("protein", help="同源蛋白 FASTA（官方位置参数）")
    ph.add_argument("dna", help="基因组 FASTA（官方位置参数）")
    ph.add_argument("--coverage_ratio", type=float, help="覆盖度阈值（教学示例 0.4）")
    ph.add_argument("--evalue", help="E-value 阈值（教学示例 1e-9）")
    ph.add_argument("--max_gene_length", type=int, help="最大基因长度（教学示例 2000）")
    ph.add_argument("--extra-args", dest="extra_args", help="透传给 homolog_genewise 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ph)

    # homolog_genewiseGFF2GFF3 [options] <genewise.gff>
    pc = sub.add_parser("gff2gff3", help=SUBCOMMANDS["gff2gff3"])
    pc.add_argument("gff", help="待转换的 genewise GFF（官方位置参数）")
    pc.add_argument("--genome", help="基因组 FASTA（--genome）")
    pc.add_argument("--min_score", type=float, help="最小得分阈值（教学示例 15）")
    pc.add_argument("--gene_prefix", help="基因 ID 前缀（教学示例 genewise）")
    pc.add_argument("-o", "--output", help="输出 GFF3 文件（脚本写 stdout，驱动捕获落盘）")
    pc.add_argument("--extra-args", dest="extra_args", help="透传给 homolog_genewiseGFF2GFF3 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（homolog 注入 --cpu N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GenewiseSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GenewiseSkill()
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

    # genewise / gff2gff3 写 stdout；给出 --output 时落盘
    if ns.subcommand in ("genewise", "gff2gff3") and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stdout and not getattr(ns, "output", None):
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
