#!/usr/bin/env python3
"""td2 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py longorfs -t transcripts.fa -O out --min-length 90 --strand-specific --threads 8
   python main.py predict -t transcripts.fa -O out --retain-mmseqs-hits hits.m8 --psauron-all-frame --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/flrnaseq.smk/workflow/scripts/td2_longorfs.py
与 td2_predict.py：
  TD2.LongOrfs -t <fasta> -O <outdir> [--gene-trans-map <gtm>] [extra]
  TD2.Predict  -t <fasta> -O <td_dir> [--retain-mmseqs-hits] [--retain-blastp-hits] [--retain-hmmer-hits] [extra]
flrnaseq 默认参数（config.yaml td2 段）：
  longorfs_extra_params: "-m 90 -M 90 -G 1 -S --alt-start --all-stopless"
  predict_extra_params:  "--psauron-all-frame"
本驱动把上述 extra 拆为结构化参数（min_length/abs_min_length/genetic_code/strand_specific/
alt_start/all_stopless/complete_orfs_only/psauron_all_frame/all_good），仍保留 extra_args 透传。
注意：TD2 的 -O 即最终输出目录（不同于 TransDecoder 会建子目录）。
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import shutil
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 skills/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "longorfs": "提取候选最长 ORF（输出 longest_orfs.pep/cds/gff3 到 -O 目录）",
    "predict": "基于 PSAURON + 长度模型预测最终 CDS（输出 <prefix>.TD2.{pep,cds,gff3,bed}）",
}

BIN_LONGORFS = "TD2.LongOrfs"
BIN_PREDICT = "TD2.Predict"


class Td2Skill(base.SkillBase):
    software = "td2"
    binary = BIN_PREDICT  # _resolve_binary 兜底用；build_command 按子命令选二进制

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_bin(self, bin_name: str) -> str:
        """按二进制名解析路径（找不到抛错）。"""
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 td2。"
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
        """根据子命令与参数构建 TD2 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        fasta = kw.get("input") or kw.get("fasta")
        if not fasta:
            raise ValueError("缺少必填参数 input（输入转录本 FASTA）")

        tmpdir = self.make_tmpdir("td2_")
        input_fa = self._maybe_decompress(str(fasta), tmpdir)

        # 输出目录：显式 output_dir > 输入文件所在目录
        out_dir = kw.get("output_dir")
        if not out_dir:
            out_dir = str(Path(str(fasta)).parent)
        os.makedirs(out_dir, exist_ok=True)

        if subcommand == "longorfs":
            binary = self._resolve_bin(BIN_LONGORFS)
            cmd: list[str] = [binary, "-t", input_fa, "-O", out_dir]
            if kw.get("gene_trans_map"):
                cmd += ["--gene-trans-map", str(kw["gene_trans_map"])]
            if kw.get("min_length") is not None:
                cmd += ["-m", str(kw["min_length"])]
            if kw.get("abs_min_length") is not None:
                cmd += ["-M", str(kw["abs_min_length"])]
            if kw.get("genetic_code") is not None:
                cmd += ["-G", str(kw["genetic_code"])]
            if kw.get("strand_specific"):
                cmd.append("-S")
            if kw.get("alt_start"):
                cmd.append("--alt-start")
            if kw.get("all_stopless"):
                cmd.append("--all-stopless")
            if kw.get("complete_orfs_only"):
                cmd.append("--complete-orfs-only")
        else:  # predict
            binary = self._resolve_bin(BIN_PREDICT)
            cmd = [binary, "-t", input_fa, "-O", out_dir]
            if kw.get("retain_mmseqs_hits"):
                cmd += ["--retain-mmseqs-hits", str(kw["retain_mmseqs_hits"])]
            if kw.get("retain_blastp_hits"):
                cmd += ["--retain-blastp-hits", str(kw["retain_blastp_hits"])]
            if kw.get("retain_hmmer_hits"):
                cmd += ["--retain-hmmer-hits", str(kw["retain_hmmer_hits"])]
            if kw.get("psauron_all_frame"):
                cmd.append("--psauron-all-frame")
            if kw.get("all_good"):
                cmd.append("--all-good")
            if kw.get("complete_orfs_only"):
                cmd.append("--complete-orfs-only")

        # 线程注入（TD2.LongOrfs / TD2.Predict 均支持 --threads）
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["--threads", str(threads)]

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
        prog="td2-skill",
        description="td2 native 技能驱动（LongOrfs + Predict，自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # longorfs
    pl = sub.add_parser("longorfs", help=SUBCOMMANDS["longorfs"])
    pl.add_argument("-t", "--input", required=True, help="输入转录本 FASTA")
    pl.add_argument("-O", "--output-dir", help="输出目录（默认输入所在目录）")
    pl.add_argument("--gene-trans-map", dest="gene_trans_map", help="gene-to-transcript 映射文件")
    pl.add_argument("-m", "--min-length", type=int, help="长转录本最小蛋白长度 aa（默认 90）")
    pl.add_argument("-M", "--abs-min-length", type=int, help="短转录本最小蛋白长度 aa（默认 90）")
    pl.add_argument("-G", "--genetic-code", type=int, help="遗传密码（NCBI 整数代码，默认 1）")
    pl.add_argument("-S", "--strand-specific", action="store_true", help="仅分析正义链")
    pl.add_argument("--alt-start", action="store_true", help="包含替代起始密码子")
    pl.add_argument("--all-stopless", action="store_true", help="报告无终止密码子序列")
    pl.add_argument("--complete-orfs-only", action="store_true", help="丢弃无终止/起始密码子的 ORF")
    pl.add_argument("--extra-args", help="透传给 TD2.LongOrfs 的额外参数")
    _add_runtime_opts(pl)

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("-t", "--input", required=True, help="输入转录本 FASTA")
    pp.add_argument("-O", "--output-dir", help="LongOrfs 输出目录（TD2.Predict 的 -O）")
    pp.add_argument("--retain-mmseqs-hits", help="mmseqs .m8 结果证据保留")
    pp.add_argument("--retain-blastp-hits", help="blastp -outfmt 6 结果证据保留")
    pp.add_argument("--retain-hmmer-hits", help="hmmscan Pfam domain table 证据保留")
    pp.add_argument("--psauron-all-frame", action="store_true", help="要求 ORF 在跨读框 PSAURON 得分最高")
    pp.add_argument("--all-good", action="store_true", help="报告所有通过过滤的 ORF")
    pp.add_argument("--complete-orfs-only", action="store_true", help="丢弃无终止/起始密码子的 ORF")
    pp.add_argument("--extra-args", help="透传给 TD2.Predict 的额外参数")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Td2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Td2Skill()
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
