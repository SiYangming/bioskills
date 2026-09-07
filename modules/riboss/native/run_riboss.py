#!/usr/bin/env python3
"""run_riboss.py — RiboSS(0.46) 原子子命令执行器（被 native/main.py 调用，也可独立运行）。

以 argparse CLI 包装已安装的 riboss Python 包稳定入口：
  translate             riboss.orfs.translate（基础三帧翻译演示/自检）
  orf_finder            riboss.orfs.orf_finder（GTF/GFF/BED 注释 + 转录本 FASTA → 预测 ORF）
  transcriptome_assembly riboss.wrapper.transcriptome_assembly（长读/混合短读 StringTie 参考引导组装）

依赖：riboss 已安装（python>=3.12 环境，含其依赖链）；orf_finder 另需 UCSC gtfToGenePred /
genePredToBed / bedtools，transcriptome_assembly 另需 stringtie + UCSC 工具 + bedtools。
独立运行示例：
  python run_riboss.py translate ATGGTCTGA
  python run_riboss.py orf_finder --annotation ann.gtf --tx tx.fa --outdir out
  python run_riboss.py transcriptome_assembly --superkingdom Eukaryota \
      --genome genome.fa --long-reads long.bam --threads 8 --outdir asm
"""

from __future__ import annotations

import argparse
import sys


def cmd_translate(args: argparse.Namespace) -> int:
    from riboss.orfs import translate
    print(translate(args.seq))
    return 0


def cmd_orf_finder(args: argparse.Namespace) -> int:
    from riboss.orfs import orf_finder
    start_codons = args.start_codons.split(",") if args.start_codons else None
    cds_range, orf = orf_finder(
        annotation=args.annotation,
        tx=args.tx,
        ncrna=args.ncrna,
        outdir=args.outdir,
        start_codon=start_codons if start_codons else ["ATG", "CTG", "GTG", "TTG"],
    )
    print(f"orf_finder done: {len(cds_range)} CDS / {len(orf)} predicted ORFs"
          f" (side outputs: <outdir>/<ann.stem>.orf_finder.pkl.gz 等)")
    return 0


def cmd_transcriptome_assembly(args: argparse.Namespace) -> int:
    from riboss.wrapper import transcriptome_assembly
    fa, gtf = transcriptome_assembly(
        superkingdom=args.superkingdom,
        genome=args.genome,
        long_reads=args.long_reads,
        short_reads=args.short_reads,
        strandness=args.strandness,
        annotation=args.annotation,
        num_threads=args.threads,
        outdir=args.outdir,
    )
    print(f"transcriptome_assembly done: fasta={fa} gtf={gtf}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="run_riboss", description="RiboSS 原子子命令执行器")
    sub = p.add_subparsers(dest="subcommand", required=True)

    pt = sub.add_parser("translate", help="按标准密码子翻译（riboss.orfs.translate 自检）")
    pt.add_argument("seq", help="核酸序列（如 ATGGTCTGA → MV）")

    po = sub.add_parser("orf_finder", help="从注释+转录本预测 ORF（核糖体图谱上游）")
    po.add_argument("--annotation", required=True, help="基因注释 GTF/GFF3/BED/genePred")
    po.add_argument("--tx", required=True, help="转录本 FASTA")
    po.add_argument("--outdir", default=".", help="输出目录（默认 .）")
    po.add_argument("--ncrna", action="store_true", help="不移除非编码 RNA 转录本")
    po.add_argument("--start-codons", default=None,
                    help="起始密码子列表，逗号分隔（默认 ATG,CTG,GTG,TTG）")

    pa = sub.add_parser("transcriptome_assembly", help="长读/混合转录本参考引导组装")
    pa.add_argument("--superkingdom", required=True, choices=["Archaea", "Bacteria", "Eukaryota"])
    pa.add_argument("--genome", required=True, help="基因组 FASTA")
    pa.add_argument("--long-reads", required=True, help="长读比对 BAM（PacBio/ONT）")
    pa.add_argument("--short-reads", help="短读比对 BAM（Illumina，混合组装）")
    pa.add_argument("--strandness", choices=["rf", "fr"], help="链特异性（--short-reads 时需要）")
    pa.add_argument("--annotation", help="参考注释 GTF（可选）")
    pa.add_argument("--threads", type=int, default=4, help="StringTie 线程（默认 4）")
    pa.add_argument("--outdir", default=".", help="输出目录（默认 .）")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    handler = {"translate": cmd_translate,
               "orf_finder": cmd_orf_finder,
               "transcriptome_assembly": cmd_transcriptome_assembly}[args.subcommand]
    try:
        return handler(args)
    except ImportError as exc:
        print(f"[ERROR] 无法导入 riboss：{exc}\n"
              "请先安装 RiboSS（conda activate riboss / -c YangmingSi riboss=0.46），"
              "详见模块 README「环境安装」。", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
