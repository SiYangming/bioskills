#!/usr/bin/env python3
"""mirdeep2 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py mapper reads.fa -c -j -k TCGTATGCCGTCTTCTGCTTGT -l 18 -m -p cel_cluster \
       -s reads_collapsed.fa -t reads_collapsed_vs_genome.arf -v
   python main.py quantifier -p precursors.fa -m mature.fa -r reads_collapsed.fa -t cel -y 16_19
   python main.py mirdeep reads_collapsed.fa cel_cluster.fa reads.arf \
       mature_this.fa mature_other.fa precursors.fa -t C.elegans
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（依据上游 TUTORIAL.md 与 miRDeep2.pl/quantifier.pl 用法）：
  mapper      mapper.pl <reads> -c|-e [-j] [-k <adapter>] [-l N] [-m] -p <index> -s <out> -t <arf> [-v]
  mirdeep     miRDeep2.pl <reads> <genome> <arf> <mature> <other_mature> <hairpin> -t <species> [-d]
  quantifier  quantifier.pl -p <hairpin> -m <mature> -r <reads> [-t <code>] [-y <len>]
miRDeep2 脚本链路无并行参数；--threads 仅记录，不注入命令行。
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
    "mapper": "折叠 reads 并用 bowtie 比对到基因组（mapper.pl）",
    "mirdeep": "识别已知/新 miRNA（miRDeep2.pl，核心算法）",
    "quantifier": "对已知 miRBase precursor 快速定量（quantifier.pl）",
}

# 子命令 -> 二进制名
_BINARY_BY_SUBCOMMAND = {
    "mapper": "mapper.pl",
    "mirdeep": "miRDeep2.pl",
    "quantifier": "quantifier.pl",
}


class Mirdeep2Skill(base.SkillBase):
    software = "mirdeep2"
    binary = "miRDeep2.pl"

    def _resolve_subcommand_binary(self, subcommand: str) -> str:
        self.binary = _BINARY_BY_SUBCOMMAND[subcommand]
        return self._resolve_binary()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 mapper.pl / miRDeep2.pl / quantifier.pl 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_subcommand_binary(subcommand)
        cmd: list[str] = [binary]

        if subcommand == "mapper":
            reads = kw.get("reads")
            if not reads:
                raise ValueError("mapper 缺少必填参数 reads（深度测序 reads）")
            cmd.append(str(reads))
            if kw.get("input_fasta"):
                cmd.append("-c")
            if kw.get("input_fastq"):
                cmd.append("-e")
            if kw.get("remove_noncanonical"):
                cmd.append("-j")
            if kw.get("clip_adapter"):
                cmd += ["-k", str(kw["clip_adapter"])]
            if kw.get("min_length") is not None:
                cmd += ["-l", str(kw["min_length"])]
            if kw.get("collapse"):
                cmd.append("-m")
            if kw.get("genome_index"):
                cmd += ["-p", str(kw["genome_index"])]
            if kw.get("collapsed_reads_out"):
                cmd += ["-s", str(kw["collapsed_reads_out"])]
            if kw.get("arf_out"):
                cmd += ["-t", str(kw["arf_out"])]
            if kw.get("verbose"):
                cmd.append("-v")

        elif subcommand == "mirdeep":
            # 位置参数顺序：reads genome arf mature other_mature hairpin
            order = ("reads", "genome", "arf", "mature_ref", "other_mature_ref", "hairpin_ref")
            missing = [k for k in order if not kw.get(k)]
            if missing:
                raise ValueError(
                    "mirdeep 缺少必填位置参数：" + " ".join(missing)
                    + "（顺序：reads genome arf mature other_mature hairpin）"
                )
            cmd += [str(kw[k]) for k in order]
            if kw.get("species"):
                cmd += ["-t", str(kw["species"])]
            if kw.get("resume"):
                cmd.append("-d")

        elif subcommand == "quantifier":
            if kw.get("hairpin"):
                cmd += ["-p", str(kw["hairpin"])]
            if kw.get("mature"):
                cmd += ["-m", str(kw["mature"])]
            if kw.get("reads_quant"):
                cmd += ["-r", str(kw["reads_quant"])]
            if kw.get("species_code"):
                cmd += ["-t", str(kw["species_code"])]
            if kw.get("mature_length"):
                cmd += ["-y", str(kw["mature_length"])]
            if not (kw.get("hairpin") and kw.get("mature") and kw.get("reads_quant")):
                raise ValueError("quantifier 缺少必填参数：-p hairpin / -m mature / -r reads")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mirdeep2-skill",
        description="miRDeep2 native 技能驱动（miRNA 发现与定量）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # mapper
    pm = sub.add_parser("mapper", help=SUBCOMMANDS["mapper"])
    pm.add_argument("reads", help="深度测序 reads（FASTA/FASTQ）")
    pm.add_argument("-c", "--input-fasta", action="store_true", help="输入为 FASTA")
    pm.add_argument("-e", "--input-fastq", action="store_true", help="输入为 FASTQ")
    pm.add_argument("-j", "--remove-noncanonical", action="store_true", help="剔除含非规范字符的条目")
    pm.add_argument("-k", "--clip-adapter", help="3' 接头序列（裁剪）")
    pm.add_argument("-l", "--min-length", type=int, help="丢弃短于该长度的 reads（常用 18）")
    pm.add_argument("-m", "--collapse", action="store_true", help="折叠重复 reads")
    pm.add_argument("-p", "--genome-index", help="bowtie 基因组索引前缀（bowtie-build 产物）")
    pm.add_argument("-s", "--collapsed-reads-out", help="折叠后 reads 输出文件")
    pm.add_argument("-t", "--arf-out", help="reads 对基因组比对 .arf 输出文件")
    pm.add_argument("-v", "--verbose", action="store_true", help="输出详细信息")
    pm.add_argument("--extra-args", help="透传给 mapper.pl 的额外参数")
    _add_runtime_opts(pm)

    # mirdeep
    pd = sub.add_parser("mirdeep", help=SUBCOMMANDS["mirdeep"])
    pd.add_argument("reads", help="折叠后的 reads（mapper -s 产物）")
    pd.add_argument("genome", help="参考基因组 FASTA")
    pd.add_argument("arf", help="reads 对基因组比对 .arf（mapper -t 产物）")
    pd.add_argument("mature_ref", help="本物种 miRBase mature 参考")
    pd.add_argument("other_mature_ref", help="近缘物种 miRBase mature 参考（无则用 none）")
    pd.add_argument("hairpin_ref", help="本物种 miRBase precursor/hairpin 参考")
    pd.add_argument("-t", "--species", help="物种名（如 C.elegans）")
    pd.add_argument("-d", "--resume", action="store_true", help="断点续跑")
    pd.add_argument("--extra-args", help="透传给 miRDeep2.pl 的额外参数")
    _add_runtime_opts(pd)

    # quantifier
    pq = sub.add_parser("quantifier", help=SUBCOMMANDS["quantifier"])
    pq.add_argument("-p", "--hairpin", help="precursor/hairpin 参考 FASTA")
    pq.add_argument("-m", "--mature", help="mature miRNA 参考 FASTA")
    pq.add_argument("-r", "--reads-quant", dest="reads_quant", help="折叠后的 reads")
    pq.add_argument("-t", "--species-code", dest="species_code", help="3 字母物种代码（如 cel）")
    pq.add_argument("-y", "--mature-length", dest="mature_length", help="mature 长度范围（如 16_19）")
    pq.add_argument("--extra-args", help="透传给 quantifier.pl 的额外参数")
    _add_runtime_opts(pq)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（miRDeep2 脚本无并行，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Mirdeep2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Mirdeep2Skill()
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
