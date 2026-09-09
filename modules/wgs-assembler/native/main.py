#!/usr/bin/env python3
"""wgs-assembler native 标准入口驱动（Celera Assembler；说明型）。

⚠️ DEPRECATED：本模块登记的是 Celera Assembler（wgs-assembler wgs-8.3rc2，
2015-05 后停止发布，OLC 组装器；PacBioToCA / PBcR 是其 PacBio 长读纠错扩展，
属同一软件、不单独成模块）。官方 wiki 首页与 PBcR 页声明「please use Canu
instead. Celera Assembler is no longer being maintained」——新项目请改用 Canu
（PBcR 官方继任者）/ Flye / hifiasm（+ HiFi 工具链 ccs/lima）。

本驱动为「说明型 + 命令构造」：不实际运行 Celera 二进制（软件已淘汰、无新用场景），
按历史教程构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. fastqtoca：Illumina 双端 FASTQ → Celera .frg 库文件
   fastqToCA -insertsize <mean> <stddev> -libraryname <name> -mates f1,f2
2. pbcr：fastqToCA 产物（frg，trusted 短读）+ PacBio 长读 → 纠错 / 组装
   PBcR -libraryname X -s pacbio.spec [-fastq pacbio.fasta] [-genomeSize N]
        [-maxCoverage 40] [-length L] [-partitions P] illumina.frg
   （spec 内 assemble=0 时仅纠错不组装；无 frg 位置参数 → PBcR 自纠错模式）
3. runca：frg 库 + spec → runCA OLC 组装
   runCA -d <out_dir> -p <prefix> -s celera.spec <frg...>
   产物 <out_dir>/<prefix>/9-terminator/<prefix>.{ctg,scf}.fasta

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py fastqtoca --library-name pe150 --mate1 f1.fastq.gz \
       --mate2 f2.fastq.gz --frg-out illumina.frg --insertsize-mean 177 \
       --insertsize-stddev 25
   python main.py pbcr --library-name X --spec pacbio.spec \
       --fastq pacbio.fasta --genome-size 5000000 --max-coverage 40 \
       illumina.frg
   python main.py runca --out-dir celera_assembly --prefix E_coli \
       --spec celera.spec pe180.frg
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 wgs-8.3rc2（runCA / fastqToCA / PBcR 在 PATH，如
~/software/wgs-8.3rc2/Linux-amd64/bin）且 Perl 依赖 Statistics::Descriptive
可用 —— 一键安装 `bash native/install.sh`（详见 README「环境安装」）。二进制无
--version 旗标，本驱动也不执行真实装配（仅命令构造）。
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
    "fastqtoca": "Illumina 双端 FASTQ → Celera .frg（fastqToCA 命令构造；仅录入/历史复现）",
    "pbcr": "PBcR 纠错/组装命令构造（-s spec；spec assemble=0 仅纠错；已废弃，仅供历史参考）",
    "runca": "runCA OLC 组装命令构造（frg + spec → .ctg/.scf；已废弃，仅供历史参考）",
}

# 子命令 → 真实可执行名（wgs-8.3rc2 Linux-amd64/bin 下即此大小写）
_BINARIES = {"fastqtoca": "fastqToCA", "pbcr": "PBcR", "runca": "runCA"}

DEPRECATED_NOTE = (
    "⚠️ Celera Assembler (wgs-assembler) 已淘汰（上游 2015 年停更，官方建议用 Canu "
    "替代；PacBioToCA/PBcR 属本软件扩展）：本模块仅作历史参考登记，以下命令构造仅"
    "供复现历史分析，新项目请用 Canu / Flye / hifiasm。"
)


class CeleraAssemblerSkill(base.SkillBase):
    software = "wgs-assembler"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（fastqToCA / PBcR / runCA），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 wgs-8.3rc2 并把 "
                f"Linux-amd64/bin 加入 PATH（bash native/install.sh），或改用 bioconda "
                f"wgs-assembler=8.3 历史包 / quay 镜像（见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """fastqtoca / pbcr / runca：构造（不执行）历史 Celera 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "fastqtoca":
            return self._build_fastqtoca(bin_path, **kw)
        if subcommand == "pbcr":
            return self._build_pbcr(bin_path, **kw)
        if subcommand == "runca":
            return self._build_runca(bin_path, **kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    # -- fastqtoca --------------------------------------------------------- #
    def _build_fastqtoca(self, bin_path: str, **kw) -> list[str]:
        mate1 = kw.get("mate1")
        mate2 = kw.get("mate2")
        reads = kw.get("reads")
        library_name = kw.get("library_name")
        if not (mate1 and mate2) and not reads:
            raise RuntimeError("fastqtoca 需要输入：--mate1/--mate2（双端）或 --reads（单端）")
        if bool(mate1) != bool(mate2):
            raise RuntimeError("fastqtoca 双端输入需成对提供：--mate1 与 --mate2 必须同时给出")
        if mate1 and mate2 and reads:
            raise RuntimeError("--reads 与 --mate1/--mate2 不能同时提供")
        if not library_name:
            raise RuntimeError("fastqtoca 需要 --library-name（-libraryname，无空格/逗号）")

        cmd = [bin_path,
               "-insertsize",
               str(int(kw.get("insertsize_mean") or 177)),
               str(int(kw.get("insertsize_stddev") or 25)),
               "-libraryname", str(library_name)]
        if mate1 and mate2:
            cmd += ["-mates", f"{self._abspath(mate1)},{self._abspath(mate2)}"]
        else:
            cmd += ["-reads", self._abspath(reads)]
        return cmd  # stdout 即 .frg 内容（CLI 层按 --frg-out 落盘）

    # -- pbcr -------------------------------------------------------------- #
    def _build_pbcr(self, bin_path: str, **kw) -> list[str]:
        library_name = kw.get("library_name")
        spec = kw.get("spec")
        if not library_name:
            raise RuntimeError("pbcr 需要 --library-name（-libraryname，无空格/逗号）")
        if not spec:
            raise RuntimeError("pbcr 需要 --spec（-s pacbio.spec；assemble=0 仅纠错；"
                               "共享内存多核下可给空文件由 PBcR 自动探测资源）")

        cmd = [bin_path,
               "-libraryname", str(library_name),
               "-s", self._abspath(spec)]
        # 历史 hybrid 教程写法：-fastq <pacbio.fasta>；8.3 wiki 现写为 fastqFile= 位置参数
        if kw.get("fastq"):
            cmd += ["-fastq", self._abspath(kw["fastq"])]
        if kw.get("genome_size"):
            cmd += ["-genomeSize", str(int(kw["genome_size"]))]
        if kw.get("max_coverage") is not None:
            cmd += ["-maxCoverage", str(int(kw["max_coverage"]))]
        if kw.get("length") is not None:
            cmd += ["-length", str(int(kw["length"]))]
        if kw.get("partitions") is not None:
            cmd += ["-partitions", str(int(kw["partitions"]))]
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            cmd += ["-t", str(int(threads))]
        # 位置参数：高保真 frg（trusted 序列，省略则 PBcR 进入自纠错）
        if kw.get("illumina_frg"):
            cmd.append(self._abspath(kw["illumina_frg"]))
        return cmd

    # -- runca ------------------------------------------------------------- #
    def _build_runca(self, bin_path: str, **kw) -> list[str]:
        spec = kw.get("spec")
        prefix = kw.get("prefix")
        raw = kw.get("frg") or []
        frgs = [raw] if isinstance(raw, str) else [f for f in raw if f]
        if not spec:
            raise RuntimeError("runca 需要 --spec（-s celera.spec；完整模板见 "
                               "native/celera.spec.example）")
        if not prefix:
            raise RuntimeError("runca 需要 --prefix（-p <prefix>，如 E_coli）")
        if not frgs:
            raise RuntimeError("runca 需要至少一个输入 .frg（fastqToCA 产物，位置参数）")

        cmd = [bin_path,
               "-d", os.path.abspath(os.path.expanduser(str(kw.get("out_dir") or "."))),
               "-p", str(prefix),
               "-s", self._abspath(spec)]
        for frg in frgs:
            cmd.append(self._abspath(frg))
        return cmd  # 产物 <out_dir>/<prefix>/9-terminator/<prefix>.{ctg,scf}.fasta


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wgs-assembler-skill",
        description="Celera Assembler (wgs-assembler) native 技能驱动（说明型：构造"
                    "历史 runCA/PBcR 命令，已废弃，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pf = sub.add_parser("fastqtoca", help=SUBCOMMANDS["fastqtoca"])
    pf.add_argument("--insertsize-mean", type=int, default=177,
                    help="插入片段期望长度均值 bp（-insertsize，默认 177）")
    pf.add_argument("--insertsize-stddev", type=int, default=25,
                    help="插入片段标准差 bp（默认 25）")
    pf.add_argument("--library-name", required=True,
                    help="-libraryname 文库 UID 名（无空格/逗号）")
    src = pf.add_mutually_exclusive_group(required=True)
    src.add_argument("--mate1", help="Illumina 双端 read1 FASTQ（与 --mate2 配对，-mates f1,f2）")
    src.add_argument("--reads", help="单端 FASTQ（-reads；与双端二选一）")
    pf.add_argument("--mate2", help="Illumina 双端 read2 FASTQ（与 --mate1 配对）")
    pf.add_argument("--frg-out", help="把 fastqToCA 的 stdout（.frg 内容）写入此文件")
    _add_runtime_opts(pf)

    pp = sub.add_parser("pbcr", help=SUBCOMMANDS["pbcr"])
    pp.add_argument("--library-name", required=True,
                    help="-libraryname 文库 UID 名（无空格/逗号）")
    pp.add_argument("--spec", required=True,
                    help="-s pacbio.spec（CA spec 文件；assemble=0 时仅纠错不组装）")
    pp.add_argument("--fastq", help="PacBio 长读 FASTA/FASTQ（历史教程写法 -fastq；"
                                    "8.3 wiki 现写为 fastqFile= 位置参数，见 README）")
    pp.add_argument("--genome-size", type=int, help="期望基因组大小 bp（-genomeSize N）")
    pp.add_argument("--max-coverage", type=int, default=40,
                    help="截断覆盖度（-maxCoverage，默认 40）")
    pp.add_argument("--length", type=int, help="保留的 PacBio 片段最小长度（-length）")
    pp.add_argument("--partitions", type=int, help="consensus 分区数（-partitions）")
    pp.add_argument("illumina_frg", nargs="?", metavar="illumina.frg",
                    help="位置参数：fastqToCA 产出的高保真 .frg（trusted 序列；省略 → "
                         "PBcR 自纠错模式）")
    _add_runtime_opts(pp)

    pr = sub.add_parser("runca", help=SUBCOMMANDS["runca"])
    pr.add_argument("--spec", required=True,
                    help="-s celera.spec（CA spec；完整模板见 native/celera.spec.example）")
    pr.add_argument("--prefix", required=True,
                    help="-p <prefix> 组装输出前缀（如 E_coli）")
    pr.add_argument("--out-dir", default=".",
                    help="-d <dir> 组装输出目录（默认当前目录；产物在 <dir>/<prefix>/ 下）")
    pr.add_argument("frg", nargs="+", metavar="input.frg",
                    help="位置参数：fastqToCA 产出的 .frg 库文件（可多个）")
    _add_runtime_opts(pr)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin，PBcR 8.3 传 -t）或 auto（不传）。"""
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
                   help="线程数：auto（默认，不传）或正整数（PBcR 8.3 -t threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = CeleraAssemblerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CeleraAssemblerSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "frg_out") and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "runca":
        kw["frg"] = ns.frg

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    # fastqtoca：可选把 stdout（.frg 内容）落盘 —— 需要真实二进制，仅提示不伪造
    frg_out = getattr(ns, "frg_out", None)
    if ns.subcommand == "fastqtoca" and frg_out:
        print(f"[hint] 将 fastqToCA stdout 重定向写入 {os.path.abspath(frg_out)}，"
              f"例如：{' '.join(cmd)} > {os.path.abspath(frg_out)}", file=sys.stderr)
    # runca：结果格式化提示（genome_seq_clear.pl 等），仅记录不执行
    if ns.subcommand == "runca":
        print(f"[hint] 产物 <out_dir>/<prefix>/9-terminator/<prefix>.{{ctg,scf}}.fasta；"
              f"可用 genome_seq_clear.pl --seq_prefix <name> "
              f"<out_dir>/<prefix>/9-terminator/<prefix>.ctg.fasta 格式化（仅提示）",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
