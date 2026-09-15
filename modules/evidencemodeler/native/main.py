#!/usr/bin/env python3
"""evidencemodeler native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py partition --genome genome.fasta --gene_predictions gp.gff3 \
       --protein_alignments pa.gff3 --transcript_alignments ta.gff3 --repeats repeats.gff3 \
       --segmentSize 500000 --overlapSize 10000 --partition_listing partitions_list.out
   python main.py write_commands --partitions partitions_list.out --weights weights.txt \
       --genome genome.fasta -o commands.list
   python main.py parallel -c commands.list --threads 8
   python main.py recombine --partitions partitions_list.out --output_file_name evm.out
   python main.py convert_gff3 --partitions partitions_list.out --output_file_name evm.out \
       --genome genome.fasta
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（EVidenceModeler v1.1.1；脚本位于 $EVM_HOME/EvmUtils 或 PATH）：
  partition        partition_EVM_inputs.pl --genome ... --partition_listing partitions_list.out
  write_commands   write_EVM_commands.pl --partitions ... --weights ... > commands.list
  parallel         ParaFly -c commands.list -CPU N
  recombine        recombine_EVM_partial_outputs.pl --partitions ... --output_file_name evm.out
  convert_gff3     convert_EVM_outputs_to_GFF3.pl --partitions ... --output_file_name evm.out --genome ...
  weights          create_weights_file.pl -A <abinitio> -P <protein> -T <transcript>
  evm              evidence_modeler.pl --genome ... --weights ...（单次运行，结果写 stdout）
脚本按 EVM_HOME/EvmUtils、EVM_HOME/bin、PATH 惰性解析（测试时 monkeypatch）。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "partition": "基因组+证据 -> 分区列表（partition_EVM_inputs.pl）",
    "write_commands": "分区列表+权重 -> ParaFly 命令列表（write_EVM_commands.pl，写 stdout）",
    "parallel": "命令列表 -> 并行执行各分区 EVM（ParaFly -CPU N）",
    "recombine": "各分区 evm.out -> 合并结果（recombine_EVM_partial_outputs.pl）",
    "convert_gff3": "各分区 evm.out -> GFF3（convert_EVM_outputs_to_GFF3.pl）",
    "weights": "证据来源程序名 -> 权重文件（create_weights_file.pl，写 stdout）",
    "evm": "单次运行 EVidenceModeler（evidence_modeler.pl；conda≥2.0 为 EVidenceModeler，写 stdout）",
}

# 子命令 -> （首选脚本名, 备选脚本名）
SCRIPTS = {
    "partition": ("partition_EVM_inputs.pl", None),
    "write_commands": ("write_EVM_commands.pl", None),
    "parallel": ("ParaFly", None),
    "recombine": ("recombine_EVM_partial_outputs.pl", None),
    "convert_gff3": ("convert_EVM_outputs_to_GFF3.pl", None),
    "weights": ("create_weights_file.pl", None),
    "evm": ("evidence_modeler.pl", "EVidenceModeler"),
}

# 这些子命令结果写 stdout（main() 在提供 -o/--output 时落盘）
STDOUT_SUBCOMMANDS = {"write_commands", "weights", "evm"}


class EvidenceModelerSkill(base.SkillBase):
    software = "evidencemodeler"
    binary = "evidence_modeler.pl"

    def _resolve_script(self, subcommand: str) -> str:
        """惰性解析 EVM 脚本路径（EVM_HOME/EvmUtils、EVM_HOME/bin、PATH）。"""
        names = [n for n in SCRIPTS[subcommand] if n]
        home = os.environ.get("EVM_HOME")
        if home:
            for name in names:
                for cand in (Path(home) / "EvmUtils" / name, Path(home) / "bin" / name,
                             Path(home) / name):
                    if cand.is_file():
                        return str(cand)
        for name in names:
            found = base.which(name)
            if found:
                return found
        raise RuntimeError(
            f"未找到 EVM 脚本 {'/'.join(names)}：请先通过 conda（evidencemodeler）或官方镜像安装，"
            f"或设置 EVM_HOME 指向 EVM 安装目录（EvmUtils/ 所在层）。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 EVM 脚本命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        script = self._resolve_script(subcommand)
        cmd: list[str] = [script]
        out_name = kw.get("output_file_name") or "evm.out"

        if subcommand == "partition":
            if kw.get("genome"):
                cmd += ["--genome", str(kw["genome"])]
            if kw.get("gene_predictions"):
                cmd += ["--gene_predictions", str(kw["gene_predictions"])]
            if kw.get("protein_alignments"):
                cmd += ["--protein_alignments", str(kw["protein_alignments"])]
            if kw.get("transcript_alignments"):
                cmd += ["--transcript_alignments", str(kw["transcript_alignments"])]
            if kw.get("repeats"):
                cmd += ["--repeats", str(kw["repeats"])]
            if kw.get("segment_size") is not None:
                cmd += ["--segmentSize", str(kw["segment_size"])]
            if kw.get("overlap_size") is not None:
                cmd += ["--overlapSize", str(kw["overlap_size"])]
            listing = kw.get("partition_listing") or kw.get("output")
            if not listing:
                raise ValueError("partition 缺少必填参数 partition_listing（分区列表输出路径）")
            cmd += ["--partition_listing", str(listing)]

        elif subcommand == "write_commands":
            partitions = kw.get("partitions")
            if not partitions:
                raise ValueError("write_commands 缺少必填参数 partitions（分区列表文件）")
            cmd += ["--partitions", str(partitions)]
            cmd += ["--output_file_name", str(out_name)]
            for key, opt in (("genome", "--genome"), ("gene_predictions", "--gene_predictions"),
                             ("protein_alignments", "--protein_alignments"),
                             ("transcript_alignments", "--transcript_alignments"),
                             ("repeats", "--repeats"), ("weights", "--weights")):
                if kw.get(key):
                    cmd += [opt, str(kw[key])]

        elif subcommand == "parallel":
            cmds = kw.get("commands_file") or kw.get("input")
            if not cmds:
                raise ValueError("parallel 缺少必填参数 commands_file（-c 命令列表）")
            cmd += ["-c", str(cmds), "-CPU", str(self._effective_threads(subcommand, kw.get("threads")))]

        elif subcommand == "recombine":
            partitions = kw.get("partitions")
            if not partitions:
                raise ValueError("recombine 缺少必填参数 partitions（分区列表文件）")
            cmd += ["--partitions", str(partitions), "--output_file_name", str(out_name)]

        elif subcommand == "convert_gff3":
            partitions = kw.get("partitions")
            if not partitions:
                raise ValueError("convert_gff3 缺少必填参数 partitions（分区列表文件）")
            cmd += ["--partitions", str(partitions), "--output_file_name", str(out_name)]
            if kw.get("genome"):
                cmd += ["--genome", str(kw["genome"])]

        elif subcommand == "weights":
            for key, opt in (("ab_initio_progs", "-A"), ("protein_progs", "-P"),
                             ("transcript_progs", "-T")):
                if kw.get(key):
                    cmd += [opt, str(kw[key])]

        elif subcommand == "evm":
            if kw.get("genome"):
                cmd += ["--genome", str(kw["genome"])]
            if kw.get("gene_predictions"):
                cmd += ["--gene_predictions", str(kw["gene_predictions"])]
            if kw.get("protein_alignments"):
                cmd += ["--protein_alignments", str(kw["protein_alignments"])]
            if kw.get("transcript_alignments"):
                cmd += ["--transcript_alignments", str(kw["transcript_alignments"])]
            if kw.get("repeats"):
                cmd += ["--repeats", str(kw["repeats"])]
            if kw.get("weights"):
                cmd += ["--weights", str(kw["weights"])]

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
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_evidence_opts(p: argparse.ArgumentParser, with_weights: bool = False) -> None:
    p.add_argument("--genome", help="基因组 FASTA")
    p.add_argument("--gene-predictions", dest="gene_predictions", help="从头预测 GFF3")
    p.add_argument("--protein-alignments", dest="protein_alignments", help="蛋白比对证据 GFF3")
    p.add_argument("--transcript-alignments", dest="transcript_alignments", help="转录本比对证据 GFF3")
    p.add_argument("--repeats", help="重复序列注释 GFF3")
    if with_weights:
        p.add_argument("--weights", help="证据权重文件")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="evidencemodeler-skill",
        description="evidencemodeler native 技能驱动（自动并行线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # partition
    pp = sub.add_parser("partition", help=SUBCOMMANDS["partition"])
    _add_evidence_opts(pp)
    pp.add_argument("--segment-size", dest="segment_size", type=int, help="分区大小 bp（默认 500000）")
    pp.add_argument("--overlap-size", dest="overlap_size", type=int, help="分区重叠 bp（默认 10000）")
    pp.add_argument("--partition-listing", dest="partition_listing", help="分区列表输出路径")
    pp.add_argument("-o", "--output", help="分区列表输出路径别名")
    pp.add_argument("--extra-args", help="透传给 partition_EVM_inputs.pl 的额外参数")
    _add_runtime_opts(pp)

    # write_commands
    pw = sub.add_parser("write_commands", help=SUBCOMMANDS["write_commands"])
    _add_evidence_opts(pw, with_weights=True)
    pw.add_argument("--partitions", help="分区列表文件")
    pw.add_argument("--output-file-name", dest="output_file_name", help="分区输出基名（默认 evm.out）")
    pw.add_argument("-o", "--output", help="命令列表输出路径（默认写 stdout）")
    pw.add_argument("--extra-args", help="透传给 write_EVM_commands.pl 的额外参数")
    _add_runtime_opts(pw)

    # parallel
    pl = sub.add_parser("parallel", help=SUBCOMMANDS["parallel"])
    pl.add_argument("-c", "--commands-file", dest="commands_file", help="ParaFly 命令列表")
    pl.add_argument("--input", help="ParaFly 命令列表别名")
    pl.add_argument("--extra-args", help="透传给 ParaFly 的额外参数")
    _add_runtime_opts(pl)

    # recombine
    pr = sub.add_parser("recombine", help=SUBCOMMANDS["recombine"])
    pr.add_argument("--partitions", help="分区列表文件")
    pr.add_argument("--output-file-name", dest="output_file_name", help="分区输出基名（默认 evm.out）")
    pr.add_argument("--extra-args", help="透传给 recombine_EVM_partial_outputs.pl 的额外参数")
    _add_runtime_opts(pr)

    # convert_gff3
    pc = sub.add_parser("convert_gff3", help=SUBCOMMANDS["convert_gff3"])
    pc.add_argument("--partitions", help="分区列表文件")
    pc.add_argument("--output-file-name", dest="output_file_name", help="分区输出基名（默认 evm.out）")
    pc.add_argument("--genome", help="基因组 FASTA")
    pc.add_argument("--extra-args", help="透传给 convert_EVM_outputs_to_GFF3.pl 的额外参数")
    _add_runtime_opts(pc)

    # weights
    pw2 = sub.add_parser("weights", help=SUBCOMMANDS["weights"])
    pw2.add_argument("-A", "--ab-initio-progs", dest="ab_initio_progs", help="从头预测程序名（逗号分隔）")
    pw2.add_argument("-P", "--protein-progs", dest="protein_progs", help="蛋白证据来源（逗号分隔）")
    pw2.add_argument("-T", "--transcript-progs", dest="transcript_progs", help="转录本证据来源（逗号分隔）")
    pw2.add_argument("-o", "--output", help="权重文件输出路径（默认写 stdout）")
    pw2.add_argument("--extra-args", help="透传给 create_weights_file.pl 的额外参数")
    _add_runtime_opts(pw2)

    # evm
    pe = sub.add_parser("evm", help=SUBCOMMANDS["evm"])
    _add_evidence_opts(pe, with_weights=True)
    pe.add_argument("-o", "--output", help="预测 GFF 输出路径（默认写 stdout）")
    pe.add_argument("--extra-args", help="透传给 EVM 主程序的额外参数")
    _add_runtime_opts(pe)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = EvidenceModelerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EvidenceModelerSkill()
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

    # stdout 型子命令在提供 -o/--output 时落盘
    if ns.subcommand in STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
