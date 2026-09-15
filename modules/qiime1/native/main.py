#!/usr/bin/env python3
"""qiime1 native 标准入口驱动（QIIME 1.9.1；说明型）。

⚠️ DEPRECATED：本模块登记的是 QIIME 1.9.1（第一代微生物组分析工具包，基于 Python 2.7，
2018 年停止维护，Py2.7 已于 2020-01 EOL）。新项目请使用 qiime2（DADA2/Deblur ASV 工作流）。

本驱动为「说明型 + 命令构造」：不实际运行 QIIME 1 脚本（软件已淘汰），按各脚本参数构造
历史命令行并打印，供历史复现 / 文档化调用 / Agent 展示。覆盖 15 个常用脚本：
  validate_mapping_file.py · join_paired_ends.py · split_libraries_fastq.py ·
  pick_open_reference_otus.py · parallel_identify_chimeric_seqs.py · filter_fasta.py ·
  make_otu_table.py · filter_alignment.py · make_phylogeny.py · summarize_taxa_through_plots.py ·
  beta_diversity_through_plots.py · alpha_rarefaction.py · print_qiime_config.py ·
  assign_taxonomy.py · pick_otus.py

两种调用模式：
1. CLI 直跑（人类 / Shell；脚本参数原样透传）：
   python main.py validate_mapping_file -m mapping.txt -o 01.mapping_file_output
   python main.py pick_open_reference_otus -i seqs.fna -p parameters_otu.txt -o out -a --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：仅对支持 -O 并行作业的脚本（pick_open_reference_otus / parallel_identify_chimeric_seqs）
注入 `-O <n>`；其余脚本线程仅作调度参考。临时目录经进程 TMPDIR 环境变量注入。
前置：已安装 QIIME 1.9.1（各脚本在 PATH，bioconda qiime=1.9.1，见 README「环境安装」）。
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

# 子命令（脚本名去 .py）-> 实际脚本文件名
SCRIPTS = {
    "validate_mapping_file": "validate_mapping_file.py",
    "join_paired_ends": "join_paired_ends.py",
    "split_libraries_fastq": "split_libraries_fastq.py",
    "pick_open_reference_otus": "pick_open_reference_otus.py",
    "parallel_identify_chimeric_seqs": "parallel_identify_chimeric_seqs.py",
    "filter_fasta": "filter_fasta.py",
    "make_otu_table": "make_otu_table.py",
    "filter_alignment": "filter_alignment.py",
    "make_phylogeny": "make_phylogeny.py",
    "summarize_taxa_through_plots": "summarize_taxa_through_plots.py",
    "beta_diversity_through_plots": "beta_diversity_through_plots.py",
    "alpha_rarefaction": "alpha_rarefaction.py",
    "print_qiime_config": "print_qiime_config.py",
    "assign_taxonomy": "assign_taxonomy.py",
    "pick_otus": "pick_otus.py",
}

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "validate_mapping_file": "校验 mapping 文件（-m mapping.txt -o outdir）",
    "join_paired_ends": "双端序列拼接（-f R1 -r R2 -o outdir；fastq-join）",
    "split_libraries_fastq": "拆分样本 / demultiplexing（-i fastq列表 -o out -m mapping -q/-p）",
    "pick_open_reference_otus": "开放式参考 OTU 挑选（-i seqs.fna -p params -o out -a -O 4）",
    "parallel_identify_chimeric_seqs": "并行嵌合体鉴定（-i aligned -t taxonomy -r ref -m blast_fragments -O 4）",
    "filter_fasta": "按序列 id 过滤 FASTA（-f in.fa -s ids.txt -n -o out.fa）",
    "make_otu_table": "构建 OTU 表（-i otu_map -t taxonomy -e exclude -o otu_table.biom）",
    "filter_alignment": "过滤比对结果（-i aligned.fa -m lanemask -o outdir）",
    "make_phylogeny": "构建系统发育树（-i aligned.fa -o tree.tre）",
    "summarize_taxa_through_plots": "物种分类统计与可视化（-i otu_table.biom -m mapping -o outdir）",
    "beta_diversity_through_plots": "Beta 多样性分析（-i otu_table.biom -m mapping -t tree -e depth -p params -o outdir）",
    "alpha_rarefaction": "Alpha 多样性稀释分析（-i otu_table.biom -m mapping -t tree -p params -o outdir）",
    "print_qiime_config": "打印 QIIME 配置与依赖自检（-tf）",
    "assign_taxonomy": "物种分类注释（-i rep_set.fa -o outdir -m rdp/uclust/blast）",
    "pick_otus": "OTU 挑选（-i seqs.fna -o outdir -m uclust -s 0.97）",
}

# 支持 -O 并行作业的脚本（其余动作不注入线程）
THREAD_FLAG = {
    "pick_open_reference_otus": "-O",
    "parallel_identify_chimeric_seqs": "-O",
}

DEPRECATED_NOTE = (
    "⚠️ QIIME 1.9.1 已淘汰（2018 停止维护、Python 2.7 EOL，OTU 工作流被 QIIME 2 取代）："
    "本模块仅作历史参考登记，以下命令构造仅供复现历史分析，新项目请用 qiime2。"
)


class Qiime1Skill(base.SkillBase):
    software = "qiime1"

    def _resolve_script(self, subcommand: str) -> str:
        """按子命令解析脚本可执行文件（如 validate_mapping_file.py），找不到会抛错。"""
        try:
            script = SCRIPTS[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SCRIPTS)}）")
        path = base.which(script)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{script}'：请先安装 QIIME 1.9.1 并把其脚本目录加入 PATH"
                f"（mamba create -n qiime1-native -c conda-forge -c bioconda qiime=1.9.1，"
                f"见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造（不执行）历史 QIIME 1 脚本命令行。"""
        if subcommand not in SCRIPTS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SCRIPTS)}）")
        script_path = self._resolve_script(subcommand)
        cmd: list[str] = [script_path]

        extra = kw.get("args") or []
        if isinstance(extra, str):
            extra = extra.split()
        cmd += [str(a) for a in extra]

        # 线程注入：仅对支持 -O 并行作业的脚本；用户已自带 -O 则不覆盖
        flag = THREAD_FLAG.get(subcommand)
        if flag and flag not in cmd:
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += [flag, str(threads)]

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="qiime1-skill",
        description="qiime1 native 技能驱动（QIIME 1.9.1，说明型：构造历史脚本命令，已废弃，仅供历史参考）",
        allow_abbrev=False,
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")
    for name, desc in SUBCOMMANDS.items():
        sp = sub.add_parser(name, help=desc, description=desc, allow_abbrev=False)
        sp.add_argument("args", nargs="*", help="脚本参数（原样透传）")
        _add_runtime_opts(sp)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _split_runtime_opts(tokens: list[str]) -> tuple[list[str], int | None, str | None]:
    """从子命令后的 token 中抽出 --threads/--tmpdir，其余脚本参数保持原始顺序。"""
    rest: list[str] = []
    threads: int | None = None
    tmpdir: str | None = None
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "--threads" and i + 1 < len(tokens):
            threads = int(tokens[i + 1]); i += 2; continue
        if t.startswith("--threads="):
            threads = int(t.split("=", 1)[1]); i += 1; continue
        if t == "--tmpdir" and i + 1 < len(tokens):
            tmpdir = tokens[i + 1]; i += 2; continue
        if t.startswith("--tmpdir="):
            tmpdir = t.split("=", 1)[1]; i += 1; continue
        rest.append(t)
        i += 1
    return rest, threads, tmpdir


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        width = max(len(k) for k in SUBCOMMANDS)
        for k, v in SUBCOMMANDS.items():
            print(f"{k:{width}s}  {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(Qiime1Skill().schema(), indent=2, ensure_ascii=False))
        return 0

    if not args or args[0] in ("-h", "--help"):
        build_parser().print_help(sys.stdout if args else sys.stderr)
        return 0 if args else 2

    subcommand, rest = args[0], args[1:]
    if subcommand not in SUBCOMMANDS:
        print(f"[ERROR] 未知子命令: {subcommand}（--list-commands 查看支持的子命令）",
              file=sys.stderr)
        return 2

    action_args, threads, tmpdir = _split_runtime_opts(rest)
    skill = Qiime1Skill()
    if tmpdir:
        skill.tmpdir = tmpdir
        skill.env_vars["TMPDIR"] = tmpdir

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(subcommand, args=action_args, threads=threads)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
