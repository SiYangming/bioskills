#!/usr/bin/env python3
"""allpathslg native 标准入口驱动（ALLPATHS-LG；说明型）。

⚠️ DEPRECATED：本模块登记的是 Broad Institute 的短读 de novo 组装器 ALLPATHS-LG
（最后源码 r52488，~2013 后停更）。Broad FTP（ftp.broadinstitute.org）已关闭、
官网页面下线 → 官方分发点失效。软件包同时含 FindErrors（ErrorCorrectReads.pl）
与 KmerSpectrumPlot.pl 两个 QC 子工具。新项目请改用 SPAdes / MaSuRCA 等替代。

本驱动为「说明型 + 命令构造」：不实际运行（软件已淘汰、官方下载点下线），按历史
教程构造命令行（KEY=VALUE 形态），供历史复现 / 文档化调用 / Agent 展示：
1. prepare：准备输入（PrepareAllPathsInputs.pl）
   PrepareAllPathsInputs.pl DATA_DIR=$PWD/<org>.genome/data PLOIDY=1 \
     IN_GROUPS_CSV=in_groups.csv IN_LIBS_CSV=in_libs.csv [GENOME_SIZE=N] OVERWRITE=True
2. assemble：运行组装（RunAllPathsLG）
   RunAllPathsLG PRE=$PWD REFERENCE_NAME=<org> DATA_SUBDIR=data RUN=run \
     SUBDIR=test OVERWRITE=True MAXPAR=1
3. errorcorrect：FindErrors 双端纠错（ErrorCorrectReads.pl）
   ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=illumina [KEEP_KMER_SPECTRA=1] \
     [FILL_FRAGMENTS=1] PAIRED_READS_A_IN=r1.fastq PAIRED_READS_B_IN=r2.fastq \
     PLOIDY=1 PAIRED_SEP=68 PAIRED_STDEV=66
4. kspec：k-mer 频谱图（KmerSpectrumPlot.pl，在 <READS_OUT>.fastq.kspec 内运行）
   KmerSpectrumPlot.pl SPECTRA=1

两种调用模式：
1. CLI 直跑（人类 / Shell）：python main.py <subcommand> --…（见各 parser help）
2. Agent Function Calling / Schema 自省：
   python main.py --schema
   python main.py --list-commands

前置：历史复现需先从存档恢复 r52488 tarball 并源码编译（见 README「环境安装」）；
驱动本身只需 python3 + pyyaml。二进制无 --version 旗标，本驱动仅命令构造、不执行。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "prepare": "PrepareAllPathsInputs.pl 输入准备（DATA_DIR/PLOIDY/IN_GROUPS_CSV/IN_LIBS_CSV；命令构造）",
    "assemble": "RunAllPathsLG 组装（PRE/REFERENCE_NAME/DATA_SUBDIR/RUN/SUBDIR；命令构造）",
    "errorcorrect": "ErrorCorrectReads.pl / FindErrors 双端纠错（PHRED_ENCODING/READS_OUT/PAIRED_*；命令构造）",
    "kspec": "KmerSpectrumPlot.pl k-mer 频谱绘图（SPECTRA=1；命令构造）",
}

# 子命令 → 真实可执行名（安装前缀 bin/ 下）
_BINARIES = {
    "prepare": "PrepareAllPathsInputs.pl",
    "assemble": "RunAllPathsLG",
    "errorcorrect": "ErrorCorrectReads.pl",
    "kspec": "KmerSpectrumPlot.pl",
}

DEPRECATED_NOTE = (
    "⚠️ ALLPATHS-LG 已淘汰（上游 ~2013 年 r52488 后停更、Broad FTP/官网已下线，官方"
    "分发点失效）：本模块仅作历史参考登记，以下命令构造仅供复现历史分析，新项目请用"
    "SPAdes / MaSuRCA 等替代。"
)


class AllpathsLgSkill(base.SkillBase):
    software = "allpathslg"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：历史复现需先从存档恢复 r52488 "
                f"tarball 源码编译并加入 PATH（见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    @staticmethod
    def _kv(key: str, value) -> str:
        return f"{key}={value}"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "prepare":
            return self._build_prepare(bin_path, **kw)
        if subcommand == "assemble":
            return self._build_assemble(bin_path, **kw)
        if subcommand == "errorcorrect":
            return self._build_errorcorrect(bin_path, **kw)
        if subcommand == "kspec":
            return [bin_path, "SPECTRA=1"]
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- prepare ----------------------------------------------------------- #
    def _build_prepare(self, bin_path: str, **kw) -> list[str]:
        data_dir = kw.get("data_dir")
        groups = kw.get("in_groups_csv")
        libs = kw.get("in_libs_csv")
        if not data_dir:
            raise RuntimeError("prepare 需要 --data-dir（DATA_DIR= 绝对路径；须与 "
                               "in_libs.csv organism_name 对应）")
        if not groups:
            raise RuntimeError("prepare 需要 --in-groups-csv（IN_GROUPS_CSV= 分组表）")
        if not libs:
            raise RuntimeError("prepare 需要 --in-libs-csv（IN_LIBS_CSV= 文库表）")

        cmd = [bin_path,
               self._kv("DATA_DIR", self._abspath(data_dir)),
               self._kv("PLOIDY", str(int(kw.get("ploidy") or 1))),
               self._kv("IN_GROUPS_CSV", self._abspath(groups)),
               self._kv("IN_LIBS_CSV", self._abspath(libs))]
        if kw.get("genome_size"):
            cmd.append(self._kv("GENOME_SIZE", str(int(kw["genome_size"]))))
        cmd.append("OVERWRITE=True")
        return cmd

    # -- assemble ---------------------------------------------------------- #
    def _build_assemble(self, bin_path: str, **kw) -> list[str]:
        ref_name = kw.get("ref_name")
        pre = kw.get("pre")
        if not ref_name:
            raise RuntimeError("assemble 需要 --ref-name（REFERENCE_NAME= organism 名，"
                               "同 in_libs.csv）")
        if not pre:
            raise RuntimeError("assemble 需要 --pre（PRE= 含 organism/data 的工作根目录）")

        cmd = [bin_path,
               self._kv("PRE", self._abspath(pre)),
               self._kv("REFERENCE_NAME", str(ref_name)),
               self._kv("DATA_SUBDIR", str(kw.get("data_subdir") or "data")),
               self._kv("RUN", str(kw.get("run") or "run")),
               self._kv("SUBDIR", str(kw.get("subdir") or "test")),
               "OVERWRITE=True",
               self._kv("MAXPAR", str(int(kw.get("maxpar") or 1)))]
        return cmd

    # -- errorcorrect (FindErrors) ---------------------------------------- #
    def _build_errorcorrect(self, bin_path: str, **kw) -> list[str]:
        reads_out = kw.get("reads_out")
        r1 = kw.get("paired_reads_a")
        r2 = kw.get("paired_reads_b")
        sep = kw.get("paired_sep")
        if not reads_out:
            raise RuntimeError("errorcorrect 需要 --reads-out（READS_OUT= 输出前缀）")
        if not (r1 and r2):
            raise RuntimeError("errorcorrect 需要 --paired-reads-a/--paired-reads-b 双端输入")
        if sep is None:
            raise RuntimeError("errorcorrect 需要 --paired-sep（PAIRED_SEP= 插入片段长度 bp；"
                               "jumping 数据先 rc 再纠错再 rc 还原）")

        cmd = [bin_path,
               self._kv("PHRED_ENCODING", str(int(kw.get("phred_encoding") or 33))),
               self._kv("READS_OUT", str(reads_out))]
        if kw.get("keep_kspec"):
            cmd.append("KEEP_KMER_SPECTRA=1")
        if kw.get("fill_fragments"):
            cmd.append("FILL_FRAGMENTS=1")
        cmd += [self._kv("PAIRED_READS_A_IN", self._abspath(r1)),
                self._kv("PAIRED_READS_B_IN", self._abspath(r2)),
                self._kv("PLOIDY", str(int(kw.get("ploidy") or 1))),
                self._kv("PAIRED_SEP", str(int(sep)))]
        if kw.get("paired_stdev") is not None:
            cmd.append(self._kv("PAIRED_STDEV", str(int(kw["paired_stdev"]))))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="allpathslg-skill",
        description="ALLPATHS-LG native 技能驱动（说明型：构造历史 RunAllPathsLG / "
                    "FindErrors / KmerSpectrumPlot 命令，已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("prepare", help=SUBCOMMANDS["prepare"])
    pp.add_argument("--data-dir", required=True, help="DATA_DIR= 绝对路径输出目录")
    pp.add_argument("--in-groups-csv", required=True, help="IN_GROUPS_CSV= 分组表路径")
    pp.add_argument("--in-libs-csv", required=True, help="IN_LIBS_CSV= 文库表路径")
    pp.add_argument("--ploidy", type=int, default=1, help="PLOIDY=（1/2，默认 1）")
    pp.add_argument("--genome-size", type=int, help="GENOME_SIZE= 期望基因组大小 bp（可选）")
    _add_runtime_opts(pp)

    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("--pre", required=True, help="PRE= 工作根目录（含 organism/data）")
    pa.add_argument("--ref-name", required=True, help="REFERENCE_NAME= organism 名")
    pa.add_argument("--data-subdir", default="data", help="DATA_SUBDIR=（默认 data）")
    pa.add_argument("--run", default="run", help="RUN=（默认 run）")
    pa.add_argument("--subdir", default="test", help="SUBDIR=（默认 test）")
    pa.add_argument("--maxpar", type=int, default=1, help="MAXPAR=（默认 1）")
    _add_runtime_opts(pa)

    pe = sub.add_parser("errorcorrect", help=SUBCOMMANDS["errorcorrect"])
    pe.add_argument("--reads-out", required=True, help="READS_OUT= 输出前缀")
    pe.add_argument("--paired-reads-a", required=True, help="PAIRED_READS_A_IN= R1 FASTQ")
    pe.add_argument("--paired-reads-b", required=True, help="PAIRED_READS_B_IN= R2 FASTQ")
    pe.add_argument("--phred-encoding", type=int, default=33, help="PHRED_ENCODING=（默认 33）")
    pe.add_argument("--paired-sep", type=int, required=True,
                    help="PAIRED_SEP= 插入片段长度 bp")
    pe.add_argument("--paired-stdev", type=int, help="PAIRED_STDEV= 标准差")
    pe.add_argument("--ploidy", type=int, default=1, help="PLOIDY=（默认 1）")
    pe.add_argument("--keep-kspec", action="store_true",
                    help="加 KEEP_KMER_SPECTRA=1（保留频谱供 kspec 绘图）")
    pe.add_argument("--fill-fragments", action="store_true",
                    help="加 FILL_FRAGMENTS=1（overlap 双端连成更长序列）")
    _add_runtime_opts(pe)

    pk = sub.add_parser("kspec", help=SUBCOMMANDS["kspec"])
    pk.add_argument("--spectra", action="store_true", default=True,
                    help="SPECTRA=1（默认开；在 <READS_OUT>.fastq.kspec 目录内运行）")
    _add_runtime_opts(pk)
    return p


def _threads_arg(value: str) -> int | str:
    v = str(value).strip().lower()
    if v == "auto":
        return "auto"
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=_threads_arg, default=None,
                   help="线程数：auto（默认）或正整数（占位，旧版多用 MAXPAR）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = AllpathsLgSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AllpathsLgSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand == "assemble":
        print("[hint] 产物 <PRE>/<REFERENCE_NAME>/data/<RUN>/ASSEMBLIES/<SUBDIR>/"
              "final.assembly.fasta；EfastaToFasta HEAD=… SPLIT_DIR=scaffolds 拆分 "
              "（仅提示）", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
