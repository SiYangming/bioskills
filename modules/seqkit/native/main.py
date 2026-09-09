#!/usr/bin/env python3
"""seqkit native 标准入口驱动。

seqkit（shenwei356/seqkit，Go）是跨平台超快 FASTA/Q 工具集，上游是「多原子子命令」形态：
`seqkit <sub> [flags] <files>`。本驱动收敛高频子集为 9 个技能子命令，白名单参数对齐官方 usage
页 v2.13.0 flags（https://bioinf.shenwei.me/seqkit/usage/；不臆造 flag，白名单外参数经
--extra-args 透传）：

  stats     seqkit stats [-a] [-T] [-b] [-e] [-S] [-N 50,90] <files...>
  fx2tab    seqkit fx2tab [-n] [-l] [-g] [-i] [-H] <file>
  grep      seqkit grep [-p <pat> | -f <file>] [-v] [-n|-s] [-i] [-r] <file>
  sample    seqkit sample [-n N | -p prop] [-s seed] [-r] <file>
  rmdup     seqkit rmdup [-s|-n] [-i] [-P] [-d <dup>] <file>
  sort      seqkit sort [-n|-l|-s] [-r] [-N] [-i] <file>
  split     seqkit split [-s N | -p N | -i] [-O <dir>] [-f] <file>
  translate seqkit translate [-f frame] [-T table] [--trim] [-M] [-x] <file>
  fq2fa     seqkit fq2fa <file>

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py stats -a -T reads_1.fq.gz reads_2.fq.gz -o fastq_stats.tsv
   python main.py grep -f id_list.txt input.fasta -v -o filtered.fasta
   python main.py translate input.cds.fa -o proteins.fa --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

每个子命令自动注入 -j 线程（seqkit 全局 flag，缺省取 meta optimization：stats/sort/split 8、
其余 4）与 -o/--out-file（缺省 stdout，.gz 自动 gzip）；--tmpdir 透传 TMPDIR 环境变量。
--dry-run 可放在任意位置：只打印构造出的命令，不执行。
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
    "stats": "序列文件统计（num_seqs/sum_len/GC/N50；-a 全量字段、-T 制表、-N 追加 N50-like 列）",
    "fx2tab": "FASTA/Q 转制表（-n 仅名称、-l 长度、-g GC、-i ID、-H 表头）",
    "grep": "按 ID/名称/序列模式检索（-p 模式/-f 模式文件，-v 反向，-n 全名，-s 按序列，-r 正则）",
    "sample": "随机抽样（-n 条数 / -p 比例；-s 种子默认 11，双端同种子保持配对）",
    "rmdup": "去重（默认按 ID；-s 按序列、-n 按全名；-d 导出重复序列）",
    "sort": "序列排序（-n 名称 / -l 长度 / -s 序列；-r 反向、-N 自然序）",
    "split": "分割（-s 每文件条数 / -p 份数 / -i 按 ID；-O 输出目录默认 $infile.split）",
    "translate": "DNA→蛋白翻译（-f 翻译框、-T 密码子表默认 1、--trim 去右端 X/*）",
    "fq2fa": "FASTQ 转 FASTA（纯转换，管道友好）",
}

# store_true 布尔参数 -> seqkit flag（kwarg 名与 meta.yaml inputs 一致）
BOOL_FLAGS = {
    "stats": {
        "all_stats": "-a",
        "tabular": "-T",
        "basename": "-b",
        "skip_err": "-e",
        "skip_file_check": "-S",
    },
    "fx2tab": {
        "only_name": "-n",
        "length_col": "-l",
        "gc_col": "-g",
        "only_id": "-i",
        "header_line": "-H",
    },
    "grep": {
        "invert_match": "-v",
        "by_name": "-n",
        "by_seq": "-s",
        "ignore_case": "-i",
        "use_regexp": "-r",
        "only_positive_strand": "-P",
    },
    "sample": {"non_deterministic": "-r"},
    "rmdup": {
        "by_seq": "-s",
        "by_name": "-n",
        "ignore_case": "-i",
        "only_positive_strand": "-P",
    },
    "sort": {
        "by_name": "-n",
        "by_length": "-l",
        "by_seq": "-s",
        "reverse": "-r",
        "natural_order": "-N",
        "ignore_case": "-i",
    },
    "split": {"by_id": "-i", "force_split": "-f"},
    "translate": {
        "trim_translation": "--trim",
        "init_codon_as_m": "-M",
        "allow_unknown_codon": "-x",
        "append_frame": "-F",
        "clean": "--clean",
    },
    "fq2fa": {},
}

# 带值参数 -> seqkit flag（值为 str(kw)）
VALUE_FLAGS = {
    "stats": {"n50_like": "-N"},
    "fx2tab": {},
    "grep": {"pattern": "-p", "pattern_file": "-f"},
    "sample": {"number": "-n", "proportion": "-p", "rand_seed": "-s"},
    "rmdup": {"dup_seqs_file": "-d"},
    "sort": {},
    "split": {"by_size": "-s", "by_part": "-p", "out_dir": "-O"},
    "translate": {"frame": "-f", "transl_table": "-T", "min_len": "-m"},
    "fq2fa": {},
}

# grep 的 -p/--pattern 可重复多次（seqkit strings 多值）
MULTI_FLAGS = {"grep": {"pattern"}}


class SeqkitSkill(base.SkillBase):
    software = "seqkit"
    binary = "seqkit"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 seqkit 命令行（[bin, sub] + flags + files + extra）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        cmd: list[str] = [binary, subcommand]

        # 自动注入线程（seqkit 全局 -j）：显式 > per_subcommand_threads > default_cpus
        threads = self._effective_threads(subcommand, kw.get("threads"))
        if threads and threads > 0:
            cmd += ["-j", str(threads)]

        # 白名单布尔 flag
        for name, flag in (BOOL_FLAGS.get(subcommand) or {}).items():
            if kw.get(name):
                cmd.append(flag)
        # 白名单带值 flag（pattern 等多值：每个值单独一个 flag）
        for name, flag in (VALUE_FLAGS.get(subcommand) or {}).items():
            val = kw.get(name)
            if val is None:
                continue
            if subcommand in MULTI_FLAGS and name in MULTI_FLAGS[subcommand]:
                vals = val if isinstance(val, list) else [val]
                for v in vals:
                    cmd += [flag, str(v)]
            else:
                cmd += [flag, str(val)]

        # 输出文件（seqkit 全局 -o/--out-file；缺省 stdout）
        out_file = kw.get("out_file")
        if out_file:
            cmd += ["-o", str(out_file)]

        # 输入文件（可多个；缺省读 stdin）
        files = kw.get("files") or []
        if isinstance(files, str):
            files = [files]
        for f in files:
            cmd.append(str(f))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录/输出/透传）。"""
    p.add_argument("-o", "--out-file", dest="out_file", help="输出文件（缺省 stdout；.gz 自动 gzip）")
    p.add_argument("--threads", type=int, help="seqkit 线程数（自动注入 -j N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（透传 TMPDIR）")
    p.add_argument("--extra-args", dest="extra_args", help="白名单外 seqkit 参数原样透传（高级用法）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="seqkit-skill",
        description="seqkit native 技能驱动（FASTA/Q 工具集高频子命令；自动线程/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构造出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _files_arg(sp, nargs: str = "*") -> None:
        sp.add_argument("files", nargs=nargs, help="输入 FASTA/Q 文件（可多个；缺省读 stdin）")

    # stats（多文件）
    ps = sub.add_parser("stats", help=SUBCOMMANDS["stats"])
    _files_arg(ps)
    ps.add_argument("-a", "--all", dest="all_stats", action="store_true", help="全量统计（四分位/sum_gap/N50/Q20/Q30/GC 等）")
    ps.add_argument("-T", "--tabular", action="store_true", help="Tab 制表输出")
    ps.add_argument("-b", "--basename", action="store_true", help="仅显示文件名")
    ps.add_argument("-e", "--skip-err", dest="skip_err", action="store_true", help="跳过错误文件仅告警")
    ps.add_argument("-S", "--skip-file-check", dest="skip_file_check", action="store_true", help="跳过输入文件检查")
    ps.add_argument("-N", "--N", dest="n50_like", metavar="VALS", help='追加 N50-like 列，如 "50,90"（N90 需显式）')
    _add_runtime_opts(ps)

    # fx2tab
    pf = sub.add_parser("fx2tab", help=SUBCOMMANDS["fx2tab"])
    _files_arg(pf)
    pf.add_argument("-n", "--name", dest="only_name", action="store_true", help="仅输出名称列（无序列/质量）")
    pf.add_argument("-l", "--length", dest="length_col", action="store_true", help="附加序列长度列")
    pf.add_argument("-g", "--gc", dest="gc_col", action="store_true", help="附加 GC 含量列")
    pf.add_argument("-i", "--only-id", dest="only_id", action="store_true", help="输出 ID 而非完整 header")
    pf.add_argument("-H", "--header-line", dest="header_line", action="store_true", help="输出表头行")
    _add_runtime_opts(pf)

    # grep
    pg = sub.add_parser("grep", help=SUBCOMMANDS["grep"])
    _files_arg(pg)
    pg.add_argument("-p", "--pattern", dest="pattern", action="append", help="搜索模式（可多次 -p；默认整词匹配 ID）")
    pg.add_argument("-f", "--pattern-file", dest="pattern_file", help="模式文件（每行一个模式）")
    pg.add_argument("-v", "--invert-match", dest="invert_match", action="store_true", help="反向匹配")
    pg.add_argument("-n", "--by-name", dest="by_name", action="store_true", help="匹配完整名称而非仅 ID")
    pg.add_argument("-s", "--by-seq", dest="by_seq", action="store_true", help="按序列搜索（正负链；-P 仅正链）")
    pg.add_argument("-i", "--ignore-case", dest="ignore_case", action="store_true", help="忽略大小写")
    pg.add_argument("-r", "--use-regexp", dest="use_regexp", action="store_true", help="模式按正则部分匹配")
    pg.add_argument("-P", "--only-positive-strand", dest="only_positive_strand", action="store_true", help="仅正链")
    _add_runtime_opts(pg)

    # sample
    ps2 = sub.add_parser("sample", help=SUBCOMMANDS["sample"])
    _files_arg(ps2)
    ps2.add_argument("-n", "--number", dest="number", type=int, help="按条数抽样（大 FASTQ 慎用，载入内存）")
    ps2.add_argument("-p", "--proportion", dest="proportion", type=float, help="按比例抽样（0-1）")
    ps2.add_argument("-s", "--rand-seed", dest="rand_seed", type=int, help="随机种子（默认 11）")
    ps2.add_argument("-r", "--non-deterministic", dest="non_deterministic", action="store_true", help="基于时间的真随机")
    _add_runtime_opts(ps2)

    # rmdup
    pr = sub.add_parser("rmdup", help=SUBCOMMANDS["rmdup"])
    _files_arg(pr)
    pr.add_argument("-s", "--by-seq", dest="by_seq", action="store_true", help="按序列去重（正负链都算）")
    pr.add_argument("-n", "--by-name", dest="by_name", action="store_true", help="按完整名称去重")
    pr.add_argument("-i", "--ignore-case", dest="ignore_case", action="store_true", help="忽略大小写")
    pr.add_argument("-P", "--only-positive-strand", dest="only_positive_strand", action="store_true", help="仅正链比较")
    pr.add_argument("-d", "--dup-seqs-file", dest="dup_seqs_file", help="把重复序列写入该文件")
    _add_runtime_opts(pr)

    # sort
    pso = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    _files_arg(pso)
    pso.add_argument("-n", "--by-name", dest="by_name", action="store_true", help="按完整名称排序")
    pso.add_argument("-l", "--by-length", dest="by_length", action="store_true", help="按序列长度排序")
    pso.add_argument("-s", "--by-seq", dest="by_seq", action="store_true", help="按序列排序")
    pso.add_argument("-r", "--reverse", action="store_true", help="反向（配合 -l 即长度降序）")
    pso.add_argument("-N", "--natural-order", dest="natural_order", action="store_true", help="自然序（1,2,10 而非 1,10,2）")
    pso.add_argument("-i", "--ignore-case", dest="ignore_case", action="store_true", help="忽略大小写")
    _add_runtime_opts(pso)

    # split
    psp = sub.add_parser("split", help=SUBCOMMANDS["split"])
    _files_arg(psp)
    psp.add_argument("-s", "--by-size", dest="by_size", type=int, help="每文件 N 条序列")
    psp.add_argument("-p", "--by-part", dest="by_part", type=int, help="均分成 N 份")
    psp.add_argument("-i", "--by-id", dest="by_id", action="store_true", help="按序列 ID 分割")
    psp.add_argument("-O", "--out-dir", dest="out_dir", help="输出目录（默认 $infile.split）")
    psp.add_argument("-f", "--force", dest="force_split", action="store_true", help="覆盖已存在的输出目录")
    _add_runtime_opts(psp)

    # translate
    pt = sub.add_parser("translate", help=SUBCOMMANDS["translate"])
    _files_arg(pt)
    pt.add_argument("-f", "--frame", dest="frame", help="翻译框：1,2,3,-1,-2,-3 或 6（全部六框；默认 1）")
    pt.add_argument("-T", "--transl-table", dest="transl_table", type=int, help="密码子表/遗传码（默认 1 标准码）")
    pt.add_argument("--trim", dest="trim_translation", action="store_true", help="去除右端 X/* 字符")
    pt.add_argument("-M", "--init-codon-as-M", dest="init_codon_as_m", action="store_true", help="起始密码子译为 M")
    pt.add_argument("-x", "--allow-unknown-codon", dest="allow_unknown_codon", action="store_true", help="未知密码子译为 X")
    pt.add_argument("-F", "--append-frame", dest="append_frame", action="store_true", help="框信息追加到序列 ID")
    pt.add_argument("--clean", action="store_true", help="把 STOP 的 * 改为 X")
    pt.add_argument("-m", "--min-len", dest="min_len", type=int, help="最小氨基酸长度（配合 -s 输出子序列）")
    _add_runtime_opts(pt)

    # fq2fa（纯转换，无子命令特有参数）
    pfq = sub.add_parser("fq2fa", help=SUBCOMMANDS["fq2fa"])
    _files_arg(pfq)
    _add_runtime_opts(pfq)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在任意位置，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = SeqkitSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SeqkitSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
        return 0

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
