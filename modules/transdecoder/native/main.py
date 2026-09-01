#!/usr/bin/env python3
"""transdecoder native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py longorfs -t transcripts.fa -O out --min-protein-length 50 --strand-specific --threads 4
   python main.py predict -t transcripts.fa -O out --retain-pfam-hits pfam.domtblout --no-refine-starts --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/flrnaseq.smk/workflow/scripts/transdecoder_longorfs.py
与 transdecoder_predict.py：
  TransDecoder.LongOrfs -t <fasta> -O <base_dir> [--gene_trans_map <gtm>] [extra]
  TransDecoder.Predict  -t <fasta> -O <base_dir> [--retain_pfam_hits] [--retain_blastp_hits] [extra]
flrnaseq 默认参数（config.yaml transdecoder 段）：
  longorfs_extra_params: "-m 50 -G Universal -S --complete_orfs_only"
  predict_extra_params:  "--no_refine_starts"
本驱动把上述 extra 拆为结构化参数（min_protein_length/genetic_code/strand_specific/
complete_orfs_only/no_refine_starts/single_best_only），仍保留 extra_args 透传。
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
    "longorfs": "提取候选最长 ORF（生成 <prefix>.transdecoder_dir/ 中间目录）",
    "predict": "基于序列组成模型预测最终 CDS（输出 pep/cds/gff3/bed）",
}

# LongOrfs 二进制与 Predict 二进制（bioconda transdecoder 包同时提供两者）
BIN_LONGORFS = "TransDecoder.LongOrfs"
BIN_PREDICT = "TransDecoder.Predict"

# flrnaseq config.yaml transdecoder 段默认值（用于文档/断言参考，非强制注入）
DEFAULT_PARAMS = {
    "longorfs": {"min_protein_length": 50, "genetic_code": "Universal"},
    "predict": {"no_refine_starts": True},
}


class TransdecoderSkill(base.SkillBase):
    software = "transdecoder"
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
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 transdecoder。"
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
        """根据子命令与参数构建 TransDecoder 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        fasta = kw.get("input") or kw.get("fasta")
        if not fasta:
            raise ValueError("缺少必填参数 input（输入转录本 FASTA）")

        tmpdir = self.make_tmpdir("transdecoder_")
        input_fa = self._maybe_decompress(str(fasta), tmpdir)

        # 输出目录：显式 output_dir > 输入文件所在目录
        out_dir = kw.get("output_dir")
        if not out_dir:
            out_dir = str(Path(str(fasta)).parent)
        os.makedirs(out_dir, exist_ok=True)

        if subcommand == "longorfs":
            binary = self._resolve_bin(BIN_LONGORFS)
            cmd: list[str] = [binary, "-t", input_fa, "-O", out_dir]
            gtm = kw.get("gene_trans_map")
            if gtm:
                cmd += ["--gene_trans_map", str(gtm)]
            if kw.get("min_protein_length") is not None:
                cmd += ["-m", str(kw["min_protein_length"])]
            if kw.get("genetic_code"):
                cmd += ["-G", str(kw["genetic_code"])]
            if kw.get("strand_specific"):
                cmd.append("-S")
            if kw.get("complete_orfs_only"):
                cmd.append("--complete_orfs_only")
        else:  # predict
            binary = self._resolve_bin(BIN_PREDICT)
            cmd = [binary, "-t", input_fa, "-O", out_dir]
            if kw.get("retain_pfam_hits"):
                cmd += ["--retain_pfam_hits", str(kw["retain_pfam_hits"])]
            if kw.get("retain_blastp_hits"):
                cmd += ["--retain_blastp_hits", str(kw["retain_blastp_hits"])]
            if kw.get("single_best_only"):
                cmd.append("--single_best_only")
            if kw.get("no_refine_starts"):
                cmd.append("--no_refine_starts")
            # 线程注入（Predict 支持 --cpu）
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--cpu", str(threads)]

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
        prog="transdecoder-skill",
        description="transdecoder native 技能驱动（LongOrfs + Predict，自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # longorfs
    pl = sub.add_parser("longorfs", help=SUBCOMMANDS["longorfs"])
    pl.add_argument("-t", "--input", required=True, help="输入转录本 FASTA")
    pl.add_argument("-O", "--output-dir", help="输出目录（默认输入所在目录）")
    pl.add_argument("--gene-trans-map", dest="gene_trans_map", help="gene-to-transcript 映射文件")
    pl.add_argument("-m", "--min-protein-length", type=int, help="最小蛋白长度 aa（默认 50）")
    pl.add_argument("-G", "--genetic-code", help="遗传密码表（默认 Universal）")
    pl.add_argument("-S", "--strand-specific", action="store_true", help="仅分析正义链")
    pl.add_argument("--complete-orfs-only", action="store_true", help="仅保留完整 ORF")
    pl.add_argument("--extra-args", help="透传给 TransDecoder.LongOrfs 的额外参数")
    _add_runtime_opts(pl)

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("-t", "--input", required=True, help="输入转录本 FASTA")
    pp.add_argument("-O", "--output-dir", help="输出目录（默认输入所在目录）")
    pp.add_argument("--retain-pfam-hits", help="hmmscan Pfam domain table")
    pp.add_argument("--retain-blastp-hits", help="blastp -outfmt 6 结果")
    pp.add_argument("--single-best-only", action="store_true", help="每个转录本仅保留单一最佳 ORF")
    pp.add_argument("--no-refine-starts", action="store_true", help="禁用起始密码子精修")
    pp.add_argument("--extra-args", help="透传给 TransDecoder.Predict 的额外参数")
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
        skill = TransdecoderSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TransdecoderSkill()
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
