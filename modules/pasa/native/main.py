#!/usr/bin/env python3
"""pasa（PASApipeline）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align_assemble -c alignAssembly.config -g genome.fasta -t transcripts.fasta.clean \
       --ALIGNERS gmap,blat --TRANSDECODER --threads 8
   python main.py build_comprehensive -c alignAssembly.config -t transcripts.fasta.clean
   python main.py asmbls_to_training \
       --pasa_transcripts_fasta DB.assemblies.fasta --pasa_transcripts_gff3 DB.pasa_assemblies.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐官方流程）：
  align_assemble     Launch_PASA_pipeline.pl -c <config> -R -g <genome> -t <transcripts> -T \
                         [-u <unclean>] [--TDN <tdn>] --ALIGNERS <aligners> --CPU N \
                         [--stringent_alignment_overlap X] [--MAX_INTRON_LENGTH L] [--TRANSDECODER] \
                         [--transcribed_is_aligned_orient]
  build_comprehensive build_comprehensive_transcriptome.dbi -c <config> -t <transcripts>
  asmbls_to_training  pasa_asmbls_to_training_set.dbi --pasa_transcripts_fasta <fasta> \
                         --pasa_transcripts_gff3 <gff3>
align_assemble 自动注入线程（--CPU N）。
"""

from __future__ import annotations

import argparse
import json
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
    "align_assemble": "Launch_PASA_pipeline.pl：转录本→基因组比对并组装（--ALIGNERS/--CPU/--TRANSDECODER）",
    "build_comprehensive": "build_comprehensive_transcriptome.dbi：构建综合转录组数据库",
    "asmbls_to_training": "pasa_asmbls_to_training_set.dbi：ORF 预测 + 生成可训练基因模型 GFF3",
}

# 子命令 -> 实际可执行脚本名（PASApipeline bin/ 下）
BINARY_FOR = {
    "align_assemble": "Launch_PASA_pipeline.pl",
    "build_comprehensive": "build_comprehensive_transcriptome.dbi",
    "asmbls_to_training": "pasa_asmbls_to_training_set.dbi",
}


class PasaSkill(base.SkillBase):
    software = "pasa"
    binary = "Launch_PASA_pipeline.pl"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式：软件级 meta.yaml 位于 modules/pasa/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行脚本（Launch_PASA_pipeline.pl / *.dbi），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda pasa=2.5.3，或官方 PASApipeline.v2.5.3.FULL.tar.gz 编译后 bin/ 加入 PATH）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 PASA 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "align_assemble":
            binary = self._resolve_tool(BINARY_FOR["align_assemble"])
            config = kw.get("config")
            genome = kw.get("genome")
            transcripts = kw.get("transcripts")
            if not config:
                raise ValueError("align_assemble 缺少必填参数 config（-c 配置文件）")
            if not genome:
                raise ValueError("align_assemble 缺少必填参数 genome（-g 基因组 FASTA）")
            if not transcripts:
                raise ValueError("align_assemble 缺少必填参数 transcripts（-t 清洗后转录本 FASTA）")
            cmd: list[str] = [binary, "-c", str(config)]
            if kw.get("run_alignment", True):
                cmd.append("-R")
            cmd += ["-g", str(genome), "-t", str(transcripts)]
            if kw.get("flag_T", True):
                cmd.append("-T")
            if kw.get("unclean_transcripts"):
                cmd += ["-u", str(kw["unclean_transcripts"])]
            if kw.get("tdn"):
                cmd += ["--TDN", str(kw["tdn"])]
            cmd += ["--ALIGNERS", str(kw.get("aligners") or "gmap,blat")]
            cmd += ["--CPU", str(threads)]
            if kw.get("stringent_alignment_overlap") is not None:
                cmd += ["--stringent_alignment_overlap", str(kw["stringent_alignment_overlap"])]
            if kw.get("max_intron_length") is not None:
                cmd += ["--MAX_INTRON_LENGTH", str(kw["max_intron_length"])]
            if kw.get("transdecoder"):
                cmd.append("--TRANSDECODER")
            if kw.get("orient"):
                cmd.append("--transcribed_is_aligned_orient")

        elif subcommand == "build_comprehensive":
            binary = self._resolve_tool(BINARY_FOR["build_comprehensive"])
            config = kw.get("config")
            transcripts = kw.get("transcripts")
            if not config:
                raise ValueError("build_comprehensive 缺少必填参数 config（-c 配置文件）")
            if not transcripts:
                raise ValueError("build_comprehensive 缺少必填参数 transcripts（-t 清洗后转录本 FASTA）")
            cmd = [binary, "-c", str(config), "-t", str(transcripts)]

        else:  # asmbls_to_training
            binary = self._resolve_tool(BINARY_FOR["asmbls_to_training"])
            fasta = kw.get("transcripts_fasta")
            gff3 = kw.get("transcripts_gff3")
            if not fasta:
                raise ValueError("asmbls_to_training 缺少必填参数 transcripts_fasta（--pasa_transcripts_fasta）")
            if not gff3:
                raise ValueError("asmbls_to_training 缺少必填参数 transcripts_gff3（--pasa_transcripts_gff3）")
            cmd = [binary, "--pasa_transcripts_fasta", str(fasta),
                   "--pasa_transcripts_gff3", str(gff3)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="pasa-skill",
        description="pasa（PASApipeline）native 技能驱动（自动线程/临时目录优化；转录本辅助基因预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align_assemble
    pa = sub.add_parser("align_assemble", help=SUBCOMMANDS["align_assemble"])
    pa.add_argument("-c", "--config", required=True, help="PASA 配置文件（alignAssembly.config）")
    pa.add_argument("-g", "--genome", required=True, help="基因组 FASTA")
    pa.add_argument("-t", "--transcripts", required=True, help="seqclean 清洗后的转录本 FASTA")
    pa.add_argument("-u", "--unclean-transcripts", dest="unclean_transcripts",
                    help="原始（seqclean 前）转录本 FASTA（-u）")
    pa.add_argument("--TDN", dest="tdn", help="Trinity 转录本 ID 列表（--TDN）")
    pa.add_argument("--ALIGNERS", dest="aligners", default="gmap,blat", help="比对工具列表（默认 gmap,blat）")
    pa.add_argument("--stringent-alignment-overlap", dest="stringent_alignment_overlap", type=float,
                    help="严格比对重叠阈值（--stringent_alignment_overlap）")
    pa.add_argument("--MAX-INTRON-LENGTH", dest="max_intron_length", type=int,
                    help="最大内含子长度（--MAX_INTRON_LENGTH）")
    pa.add_argument("--TRANSDECODER", dest="transdecoder", action="store_true", help="启用 ORF 预测（--TRANSDECODER）")
    pa.add_argument("--transcribed-is-aligned-orient", dest="orient", action="store_true",
                    help="链特异性数据参数（--transcribed_is_aligned_orient）")
    pa.add_argument("--no-R", dest="run_alignment", action="store_false", help="关闭 -R（默认启用）")
    pa.add_argument("--no-T", dest="flag_T", action="store_false", help="关闭 -T（默认启用）")
    pa.add_argument("--extra-args", dest="extra_args", help="透传给 Launch_PASA_pipeline.pl 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pa)

    # build_comprehensive
    pb = sub.add_parser("build_comprehensive", help=SUBCOMMANDS["build_comprehensive"])
    pb.add_argument("-c", "--config", required=True, help="PASA 配置文件（alignAssembly.config）")
    pb.add_argument("-t", "--transcripts", required=True, help="seqclean 清洗后的转录本 FASTA")
    pb.add_argument("--extra-args", dest="extra_args",
                    help="透传给 build_comprehensive_transcriptome.dbi 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    # asmbls_to_training
    pt = sub.add_parser("asmbls_to_training", help=SUBCOMMANDS["asmbls_to_training"])
    pt.add_argument("--pasa_transcripts_fasta", dest="transcripts_fasta", required=True,
                    help="<DBName>.assemblies.fasta（--pasa_transcripts_fasta）")
    pt.add_argument("--pasa_transcripts_gff3", dest="transcripts_gff3", required=True,
                    help="<DBName>.pasa_assemblies.gff3（--pasa_transcripts_gff3）")
    pt.add_argument("--extra-args", dest="extra_args",
                    help="透传给 pasa_asmbls_to_training_set.dbi 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pt)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（align_assemble 注入 --CPU N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:20s} {v}")
        return 0
    if "--schema" in args:
        skill = PasaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PasaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir")}
    kw = {k: v for k, v in kw.items() if v is not None}
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
