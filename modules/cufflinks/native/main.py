#!/usr/bin/env python3
"""cufflinks native 标准入口驱动。

⚠️ Cufflinks 为【淘汰技术】（deprecated，最后稳定版 2.2.1）。本驱动为「命令构造」型：
按官方 man page 构造 cufflinks 套件六个子命令的命令行，供历史复现与文档化调用。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py cufflinks sample.bam -o sample -p 8 -b genome.fasta -u -L sample
   python main.py cuffmerge gtf_list.txt -o ./ -p 4 -s genome.fasta
   python main.py cuffdiff samples.txt --no-update-check -o cdiff -p 8 -L ctrl,treat -b genome.fasta -u genome.gtf
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（Tuxedo 套件）：
  cufflinks   cufflinks [<bam>] -o <dir> -p N [-G <ref.gtf>] [-M <mask.gtf>] [-b <seq.fa>] [-u] [-L <label>] [-m <mean>] [-s <stdev>] [--library-type <t>]
  cuffmerge   cuffmerge -o <dir> -p N [-g <ref.gtf>] [-s <seq.fa>] <gtf_list>
  cuffcompare cuffcompare -o <prefix> [-r <ref.gtf>] [-s <seq.fa>] [-g <gtf>] <gtf>
  cuffdiff    cuffdiff [--no-update-check] -o <dir> -p N [-L <labels>] [-b <seq.fa>] [-u <gtf>] <samples>
  cuffquant   cuffquant -o <dir> -p N [-b <seq.fa>] [-u <gtf>] <bam>
  cuffnorm    cuffnorm -o <dir> -p N [-L <labels>] <samples>
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
    "cufflinks": "转录本组装（cufflinks [<bam>] -o <dir> -p N ...）",
    "cuffmerge": "多样本 GTF 合并（cuffmerge -o <dir> -p N [-s <seq.fa>] <gtf_list>）",
    "cuffcompare": "与参考注释比较（cuffcompare -o <prefix> [-r <ref.gtf>] [-s <seq.fa>] <gtf>）",
    "cuffdiff": "差异表达分析（cuffdiff --no-update-check -o <dir> -p N -L <labels> <samples>）",
    "cuffquant": "样本表达量定量（cuffquant -o <dir> -p N [-b <seq.fa>] [-u <gtf>] <bam>）",
    "cuffnorm": "表达量归一化（cuffnorm -o <dir> -p N -L <labels> <samples>）",
}

# 子命令 -> 二进制名（与子命令同名）
_BINARY_BY_SUBCOMMAND = {k: k for k in SUBCOMMANDS}


class CufflinksSkill(base.SkillBase):
    software = "cufflinks"
    binary = "cufflinks"

    def _resolve_subcommand_binary(self, subcommand: str) -> str:
        self.binary = _BINARY_BY_SUBCOMMAND[subcommand]
        return self._resolve_binary()

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建对应 cufflinks 套件命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = [self._resolve_subcommand_binary(subcommand)]
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "cufflinks":
            if kw.get("alignment"):
                cmd.append(str(kw["alignment"]))
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-p", str(threads)]
            if kw.get("reference_gtf"):
                cmd += ["-G", str(kw["reference_gtf"])]
            if kw.get("masked_gtf"):
                cmd += ["-M", str(kw["masked_gtf"])]
            if kw.get("bias_fasta"):
                cmd += ["-b", str(kw["bias_fasta"])]
            if kw.get("multi_read_correct"):
                cmd.append("-u")
            if kw.get("labels"):
                cmd += ["-L", str(kw["labels"])]
            if kw.get("frag_len_mean") is not None:
                cmd += ["-m", str(kw["frag_len_mean"])]
            if kw.get("frag_len_stdev") is not None:
                cmd += ["-s", str(kw["frag_len_stdev"])]
            if kw.get("library_type"):
                cmd += ["--library-type", str(kw["library_type"])]

        elif subcommand == "cuffmerge":
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-p", str(threads)]
            if kw.get("gtf_annotation"):
                cmd += ["-g", str(kw["gtf_annotation"])]
            if kw.get("genome_fasta"):
                cmd += ["-s", str(kw["genome_fasta"])]
            gtf_list = kw.get("gtf_list")
            if not gtf_list:
                raise ValueError("cuffmerge 缺少必填位置参数 gtf_list（GTF 列表文件）")
            cmd.append(str(gtf_list))

        elif subcommand == "cuffcompare":
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("ref_gtf"):
                cmd += ["-r", str(kw["ref_gtf"])]
            if kw.get("genome_fasta"):
                cmd += ["-s", str(kw["genome_fasta"])]
            if kw.get("gtf_annotation"):
                cmd += ["-g", str(kw["gtf_annotation"])]
            gtf = kw.get("gtf")
            if not gtf:
                raise ValueError("cuffcompare 缺少必填位置参数 gtf（待比较 GTF）")
            cmd.append(str(gtf))

        elif subcommand == "cuffdiff":
            if kw.get("no_update_check"):
                cmd.append("--no-update-check")
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-p", str(threads)]
            if kw.get("labels"):
                cmd += ["-L", str(kw["labels"])]
            if kw.get("bias_fasta"):
                cmd += ["-b", str(kw["bias_fasta"])]
            if kw.get("gui_gtf"):
                cmd += ["-u", str(kw["gui_gtf"])]
            samples = kw.get("samples")
            if not samples:
                raise ValueError("cuffdiff 缺少必填位置参数 samples（样本文件）")
            cmd.append(str(samples))

        elif subcommand == "cuffquant":
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-p", str(threads)]
            if kw.get("bias_fasta"):
                cmd += ["-b", str(kw["bias_fasta"])]
            if kw.get("gui_gtf"):
                cmd += ["-u", str(kw["gui_gtf"])]
            alignment = kw.get("alignment")
            if not alignment:
                raise ValueError("cuffquant 缺少必填位置参数 alignment（输入 BAM）")
            cmd.append(str(alignment))

        elif subcommand == "cuffnorm":
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["-p", str(threads)]
            if kw.get("labels"):
                cmd += ["-L", str(kw["labels"])]
            samples = kw.get("samples")
            if not samples:
                raise ValueError("cuffnorm 缺少必填位置参数 samples（样本文件）")
            cmd.append(str(samples))

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
        prog="cufflinks-skill",
        description="Cufflinks native 技能驱动（Tuxedo 套件；⚠️ 淘汰技术）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # cufflinks
    pc = sub.add_parser("cufflinks", help=SUBCOMMANDS["cufflinks"])
    pc.add_argument("alignment", nargs="?", help="输入排序 BAM")
    pc.add_argument("-o", "--output", help="输出目录")
    pc.add_argument("-G", "--reference-gtf", dest="reference_gtf", help="参考注释 GTF")
    pc.add_argument("-M", "--masked-gtf", dest="masked_gtf", help="屏蔽 GTF")
    pc.add_argument("-b", "--bias-fasta", dest="bias_fasta", help="偏差校正基因组 FASTA")
    pc.add_argument("-u", "--multi-read-correct", dest="multi_read_correct", action="store_true", help="多读校正")
    pc.add_argument("-L", "--labels", help="样本标签")
    pc.add_argument("-m", "--frag-len-mean", dest="frag_len_mean", type=int, help="片段平均长度")
    pc.add_argument("-s", "--frag-len-stdev", dest="frag_len_stdev", type=int, help="片段长度标准差")
    pc.add_argument("--library-type", dest="library_type", help="文库类型（fr-unstranded 等）")
    pc.add_argument("--extra-args", help="透传给 cufflinks 的额外参数")
    _add_runtime_opts(pc)

    # cuffmerge
    pm = sub.add_parser("cuffmerge", help=SUBCOMMANDS["cuffmerge"])
    pm.add_argument("gtf_list", help="输入 GTF 列表文件")
    pm.add_argument("-o", "--output", help="输出目录")
    pm.add_argument("-g", "--gtf-annotation", dest="gtf_annotation", help="参考注释 GTF")
    pm.add_argument("-s", "--genome-fasta", dest="genome_fasta", help="基因组 FASTA")
    pm.add_argument("--extra-args", help="透传给 cuffmerge 的额外参数")
    _add_runtime_opts(pm)

    # cuffcompare
    pp = sub.add_parser("cuffcompare", help=SUBCOMMANDS["cuffcompare"])
    pp.add_argument("gtf", help="待比较 GTF")
    pp.add_argument("-o", "--output", help="输出前缀")
    pp.add_argument("-r", "--ref-gtf", dest="ref_gtf", help="参考注释 GTF")
    pp.add_argument("-s", "--genome-fasta", dest="genome_fasta", help="基因组 FASTA")
    pp.add_argument("-g", "--gtf-annotation", dest="gtf_annotation", help="参考注释 GTF（-g）")
    pp.add_argument("--extra-args", help="透传给 cuffcompare 的额外参数")
    _add_runtime_opts(pp)

    # cuffdiff
    pd = sub.add_parser("cuffdiff", help=SUBCOMMANDS["cuffdiff"])
    pd.add_argument("samples", help="样本文件（逗号分组的重复 / BAM 或 .cxb 列表）")
    pd.add_argument("-o", "--output", help="输出目录")
    pd.add_argument("-L", "--labels", help="逗号分隔的样本组名")
    pd.add_argument("-b", "--bias-fasta", dest="bias_fasta", help="偏差校正基因组 FASTA")
    pd.add_argument("-u", "--gui-gtf", dest="gui_gtf", help="校正用参考 GTF")
    pd.add_argument("--no-update-check", dest="no_update_check", action="store_true", help="跳过版本更新检查")
    pd.add_argument("--extra-args", help="透传给 cuffdiff 的额外参数")
    _add_runtime_opts(pd)

    # cuffquant
    pq = sub.add_parser("cuffquant", help=SUBCOMMANDS["cuffquant"])
    pq.add_argument("alignment", help="输入排序 BAM")
    pq.add_argument("-o", "--output", help="输出目录")
    pq.add_argument("-b", "--bias-fasta", dest="bias_fasta", help="偏差校正基因组 FASTA")
    pq.add_argument("-u", "--gui-gtf", dest="gui_gtf", help="校正用参考 GTF")
    pq.add_argument("--extra-args", help="透传给 cuffquant 的额外参数")
    _add_runtime_opts(pq)

    # cuffnorm
    pn = sub.add_parser("cuffnorm", help=SUBCOMMANDS["cuffnorm"])
    pn.add_argument("samples", help="样本文件")
    pn.add_argument("-o", "--output", help="输出目录")
    pn.add_argument("-L", "--labels", help="逗号分隔的样本组名")
    pn.add_argument("--extra-args", help="透传给 cuffnorm 的额外参数")
    _add_runtime_opts(pn)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -p N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = CufflinksSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CufflinksSkill()
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
