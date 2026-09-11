#!/usr/bin/env python3
"""trnascan-se（tRNAscan-SE 2.0）native 标准入口驱动。

tRNAscan-SE（http://lowelab.ucsc.edu/tRNAscan-SE/，上游 UCSC-LoweLab）是 tRNA 基因
预测的事实标准工具：以 Infernal covariance models 为主搜索引擎（SCFG），默认真核模型，
-B/--bacterial 切原核模型、-A 切古菌模型，输出标准表格、二级结构与统计文件。
covariance model 与 Infernal 等依赖由 bioconda trnascan-se 包随装（模型文件在包内），
本驱动不单独管理。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   # 真核默认（教学典型用法）：-o 表格 / -f 二级结构 / -m 统计
   python main.py scan genome.fasta -o tRNA.out -f tRNA.ss -m tRNA.stats --threads 4
   # 原核（-B 细菌模型）
   python main.py scan genome.ecoli.fasta -o Ecoli_tRNA.out -f Ecoli_tRNA.ss \
       -m Ecoli_tRNA.stats --prokaryote
   # 额外参数透传（如 v2.0.9+ 直接出 GFF3：-j x.gff；古菌 -A）
   python main.py scan genome.fasta -o tRNA.out --extra-args "-j tRNA.gff3"
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程说明（重要）：
- tRNAscan-SE 主程序无 -pa / -p 类线程开关（v1/v2 均无）；2.0 的搜索并行依赖
  「按序列切分 + 并发跑多个实例」（GNU parallel），或 v2.0.13+ 新增的 --thread <n>
  （转发给 Infernal cmsearch；仅默认 Infernal 模式可用，不可与 -e/-t/-C/-L 共存，
  v2.0.12 及更早不支持该参数）。
- 因此本驱动**不强加线程参数**：--threads 仅作为运行期协议位被接受、不注入命令行
  （不会把 --threads 拼进 tRNAscan-SE 调用）；确需多线程时经 --extra-args
  "--thread N" 显式透传（仅 v2.0.13+）。
- --tmpdir 会真实生效：tRNAscan-SE 2.0 读取环境变量 $TMPDIR 放置中间文件
  （源码：$ENV{TMPDIR} 优先），本驱动把 TMPDIR 注入子进程环境。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "scan": "tRNAscan-SE 2.0：预测 FASTA 中的 tRNA 基因（真核默认 / 原核 -B；-o 表格、-f 二级结构、-m 统计）",
}


class TrnaScanSESkill(base.SkillBase):
    software = "trnascan-se"
    binary = "tRNAscan-SE"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/trnascan-se/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 tRNAscan-SE 2.0 命令行。"""
        if subcommand != "scan":
            raise RuntimeError(f"未知子命令: {subcommand}")

        genome_fasta = kw.get("genome_fasta")
        if not genome_fasta:
            raise RuntimeError("scan 需要 genome_fasta（基因组/序列 FASTA，位置参数）")

        binary = self._resolve_binary()

        # 用法：tRNAscan-SE [options] <FASTA file(s)>
        # Getopt::Long bundling 解析，选项与位置参数顺序不限；这里统一选项在前。
        cmd: list[str] = [binary]

        # 搜索模型：默认真核；-B/--bacterial 切原核模型
        if kw.get("prokaryote"):
            cmd += ["-B"]

        # 输出：-o 表格（默认 stdout）、-f/--struct 二级结构、-m/--stats 统计
        out = kw.get("out")
        if out:
            cmd += ["-o", str(out)]
        ss = kw.get("ss")
        if ss:
            cmd += ["-f", str(ss)]
        stats = kw.get("stats")
        if stats:
            cmd += ["-m", str(stats)]

        # 高级透传（慎用）：-A 古菌 / -j x.gff（v2.0.9+ GFF3）/ -a x.fa / -b x.bed /
        # --thread N（v2.0.13+ Infernal 多线程，仅默认模式）等
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        cmd += [str(genome_fasta)]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="trnascan-se-skill",
        description="trnascan-se native 技能驱动（tRNAscan-SE 2.0 tRNA 基因预测；自动 TMPDIR；不强加线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # scan: tRNAscan-SE [-B] [-o out] [-f ss] [-m stats] <genome.fasta>
    ps = sub.add_parser("scan", help=SUBCOMMANDS["scan"])
    ps.add_argument("genome_fasta", help="基因组/序列 FASTA（位置参数）")
    ps.add_argument("-o", "--out", help="表格输出文件（默认 stdout；教学惯例如 tRNA.out）")
    ps.add_argument("-f", "--ss", dest="ss",
                    help="二级结构输出文件（.ss，默认不输出；教学惯例如 tRNA.ss）")
    ps.add_argument("-m", "--stats", help="统计输出文件（.stats，默认不输出；教学惯例如 tRNA.stats）")
    ps.add_argument("-B", "--prokaryote", action="store_true",
                    help="原核模型模式（-B/--bacterial；默认真核模型）")
    ps.add_argument("--extra-args", dest="extra_args",
                    help="透传给 tRNAscan-SE 的额外参数（如 -A 古菌、-j x.gff（v2.0.9+ GFF3）、"
                         "--thread 4（v2.0.13+）；高级用法，慎用）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。

    注意：--threads 为协议位——tRNAscan-SE 无 -pa，驱动不强加线程参数、不注入命令行
    （见模块 docstring）；--tmpdir 真实生效（注入 TMPDIR 环境变量，程序读取其放置中间文件）。
    """
    p.add_argument("--threads", type=int, help="覆盖默认线程数（协议位：驱动不注入，仅记录/预留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR 环境变量）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = TrnaScanSESkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TrnaScanSESkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # 非捕获类（无 stdout）的子命令直接继承退出码
    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        # scan 未给 -o 时表格走 stdout 直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
