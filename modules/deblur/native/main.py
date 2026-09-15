#!/usr/bin/env python3
"""deblur native 标准入口驱动（Deblur 去噪 CLI）。

Deblur 以 Python CLI 分发（命令 `deblur`），本驱动封装其核心子命令，并对 workflow
自动注入并行作业数（-O / --jobs-to-start）与临时目录优化。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py workflow --seqs-fp demux.fasta --output-dir out \
       --trim-length 120 --reference-fp 88_otus.fasta --threads 4
   python main.py dereplicate demux.fasta derep.fasta --min-size 2
   python main.py trim demux.fasta trimmed.fasta --trim-length 120
   python main.py build-biom-table chimera_removed_dir out_dir --min-reads 10
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

参考数据库：workflow 默认使用内置 Greengenes 13_8 OTUs 88% identity；亦可用
--reference-fp 指定 85_otus/88_otus 等参考 FASTA（可重复），--reference-db-fp 指定
已索引库目录以避免重复索引。
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
    "workflow": "完整流水线：demux fasta/fastq -> 去噪 -> BIOM 表（deblur workflow）",
    "dereplicate": "序列去重并去除低丰度（deblur dereplicate）",
    "trim": "序列截短（deblur trim）",
    "build-biom-table": "由去嵌合 fasta 目录生成 BIOM 表（deblur build-biom-table）",
}

# 仅 workflow 有并行参数（-O/--jobs-to-start）；其余子命令接受 --threads 但不注入
THREADED = {"workflow"}


def _as_list(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value]
    return [str(value)]


class DeblurSkill(base.SkillBase):
    software = "deblur"
    binary = "deblur"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "workflow":
            return self._cmd_workflow(binary, threads, kw)
        if subcommand == "dereplicate":
            return self._cmd_dereplicate(binary, kw)
        if subcommand == "trim":
            return self._cmd_trim(binary, kw)
        return self._cmd_build_biom_table(binary, kw)

    def _cmd_workflow(self, binary: str, threads: int, kw: dict) -> list[str]:
        seqs = kw.get("seqs_fp") or kw.get("input")
        outdir = kw.get("output_dir") or kw.get("output")
        trim_length = kw.get("trim_length")
        if not seqs:
            raise ValueError("workflow 缺少 --seqs-fp（输入序列文件或目录）")
        if not outdir:
            raise ValueError("workflow 缺少 --output-dir（输出目录）")
        if trim_length is None:
            raise ValueError("workflow 缺少 --trim-length（截短长度；-1 表示跳过截短）")

        cmd = [binary, "workflow", "--seqs-fp", str(seqs),
               "--output-dir", str(outdir), "--trim-length", str(int(trim_length))]
        if kw.get("left_trim_length") is not None:
            cmd += ["--left-trim-length", str(int(kw["left_trim_length"]))]
        for r in _as_list(kw.get("reference_fp")):
            cmd += ["--pos-ref-fp", r]
        for r in _as_list(kw.get("reference_db_fp")):
            cmd += ["--pos-ref-db-fp", r]
        for r in _as_list(kw.get("neg_ref_fp")):
            cmd += ["--neg-ref-fp", r]
        for r in _as_list(kw.get("neg_ref_db_fp")):
            cmd += ["--neg-ref-db-fp", r]
        if kw.get("mean_error") is not None:
            cmd += ["--mean-error", str(kw["mean_error"])]
        if kw.get("indel_prob") is not None:
            cmd += ["--indel-prob", str(kw["indel_prob"])]
        if kw.get("indel_max") is not None:
            cmd += ["--indel-max", str(int(kw["indel_max"]))]
        if kw.get("min_reads") is not None:
            cmd += ["--min-reads", str(int(kw["min_reads"]))]
        if kw.get("min_size") is not None:
            cmd += ["--min-size", str(int(kw["min_size"]))]
        if kw.get("threads_per_sample") is not None:
            cmd += ["--threads-per-sample", str(int(kw["threads_per_sample"]))]
        if kw.get("overwrite"):
            cmd.append("--overwrite")
        if kw.get("keep_tmp_files"):
            cmd.append("--keep-tmp-files")
        if kw.get("log_file"):
            cmd += ["--log-file", str(kw["log_file"])]
        if threads and threads > 0:
            cmd += ["--jobs-to-start", str(int(threads))]
        return cmd

    def _cmd_dereplicate(self, binary: str, kw: dict) -> list[str]:
        seqs = kw.get("seqs_fp") or kw.get("input")
        output = kw.get("output_fp") or kw.get("output")
        if not seqs:
            raise ValueError("dereplicate 缺少输入 seqs_fp（位置参数）")
        if not output:
            raise ValueError("dereplicate 缺少输出 output_fp（位置参数）")
        cmd = [binary, "dereplicate", str(seqs), str(output)]
        cmd += ["--min-size", str(int(kw.get("min_size", 2)))]
        return cmd

    def _cmd_trim(self, binary: str, kw: dict) -> list[str]:
        seqs = kw.get("seqs_fp") or kw.get("input")
        output = kw.get("output_fp") or kw.get("output")
        trim_length = kw.get("trim_length")
        if not seqs:
            raise ValueError("trim 缺少输入 seqs_fp（位置参数）")
        if not output:
            raise ValueError("trim 缺少输出 output_fp（位置参数）")
        if trim_length is None:
            raise ValueError("trim 缺少 --trim-length（截短长度）")
        return [binary, "trim", str(seqs), str(output), "--trim-length", str(int(trim_length))]

    def _cmd_build_biom_table(self, binary: str, kw: dict) -> list[str]:
        seqs = kw.get("seqs_fp") or kw.get("input")
        output = kw.get("output_fp") or kw.get("output")
        if not seqs:
            raise ValueError("build-biom-table 缺少输入 seqs_fp（去嵌合 fasta 目录）")
        if not output:
            raise ValueError("build-biom-table 缺少输出 output_fp（输出目录）")
        cmd = [binary, "build-biom-table", str(seqs), str(output)]
        cmd += ["--min-reads", str(int(kw.get("min_reads", 10)))]
        if kw.get("file_type"):
            cmd += ["--file_type", str(kw["file_type"])]
        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认并行作业数（workflow 映射到 -O）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="deblur-skill",
        description="deblur native 技能驱动（Deblur 去噪 CLI，自动注入并行作业数）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # workflow
    pw = sub.add_parser("workflow", help=SUBCOMMANDS["workflow"])
    pw.add_argument("--seqs-fp", help="输入序列文件或目录（demux fasta/fastq）")
    pw.add_argument("--output-dir", help="输出目录（含 BIOM 表）")
    pw.add_argument("--trim-length", type=int, help="截短长度（-1 表示跳过截短）")
    pw.add_argument("--left-trim-length", type=int, help="5' 端截短碱基数（默认 0）")
    pw.add_argument("--reference-fp", action="append",
                    help="正向参考数据库 FASTA（默认 Greengenes 88% OTUs），可重复")
    pw.add_argument("--reference-db-fp", action="append",
                    help="已索引的正向参考数据库目录，顺序对应 --reference-fp")
    pw.add_argument("--neg-ref-fp", action="append",
                    help="负向（伪影）参考数据库 FASTA（默认 PhiX+接头），可重复")
    pw.add_argument("--neg-ref-db-fp", action="append", help="已索引的负向参考数据库目录")
    pw.add_argument("--min-reads", type=int, help="研究范围最小读数（默认 10）")
    pw.add_argument("--min-size", type=int, help="每样本最小出现次数（默认 2）")
    pw.add_argument("--mean-error", type=float, help="平均每碱基错误率（默认 0.005）")
    pw.add_argument("--indel-prob", type=float, help="插入/缺失概率（默认 0.01）")
    pw.add_argument("--indel-max", type=int, help="最大允许 indel 数（默认 3）")
    pw.add_argument("--threads-per-sample", type=int, help="每样本线程数（-a；0=全部核）")
    pw.add_argument("--overwrite", action="store_true", help="输出目录已存在时覆盖")
    pw.add_argument("--keep-tmp-files", action="store_true", help="保留临时文件（调试）")
    pw.add_argument("--log-file", help="日志文件路径（默认 deblur.log）")
    _add_runtime_opts(pw)

    # dereplicate
    pd = sub.add_parser("dereplicate", help=SUBCOMMANDS["dereplicate"])
    pd.add_argument("seqs_fp", help="输入序列文件")
    pd.add_argument("output_fp", help="输出去重后 fasta")
    pd.add_argument("--min-size", type=int, default=2, help="每样本最小出现次数（默认 2）")
    _add_runtime_opts(pd)

    # trim
    pt = sub.add_parser("trim", help=SUBCOMMANDS["trim"])
    pt.add_argument("seqs_fp", help="输入序列文件")
    pt.add_argument("output_fp", help="输出截短后 fasta")
    pt.add_argument("--trim-length", type=int, required=True, help="截短长度")
    _add_runtime_opts(pt)

    # build-biom-table
    pb = sub.add_parser("build-biom-table", help=SUBCOMMANDS["build-biom-table"])
    pb.add_argument("seqs_fp", help="去嵌合 fasta 目录")
    pb.add_argument("output_fp", help="输出目录（含 all.biom）")
    pb.add_argument("--min-reads", type=int, default=10, help="研究范围最小读数（默认 10）")
    pb.add_argument("--file_type", help="收集的文件名后缀（默认 deblur 去嵌合 fasta 后缀）")
    _add_runtime_opts(pb)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = DeblurSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = DeblurSkill()
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
