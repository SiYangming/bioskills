#!/usr/bin/env python3
"""nanoseq: Nanopore RNA-seq 流程编排器。

流程（迁移自 snakemake.smk/nanoseq.smk 的 nanoseq.sh 脚本逻辑）：
  [SRA prep] -> [dorado basecall] -> minimap2 align -> samtools sort/index/flagstat
  -> FLAIR consensus（bam2bed12/annotate/collapse）
  -> StringTie（assemble/fix_gtf/merge）
  -> ORF 预测（TransDecoder/TD2）

执行模式：
  a) --dry-run：仅打印命令（默认）
  b) --real：真实调用 modules/<sw>/native/main.py
  c) --list-stages：列出 stages

编排原则：只做流程串联，每个 step 委托给 modules/<sw>/native/main.py。
"""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent / "modules"  # modules/


def _native_cmd(software: str, subcmd: list[str], threads: int | None = None) -> list[str]:
    native = _SKILLS_ROOT / software / "native" / "main.py"
    if not native.exists():
        return ["<MISSING>", str(native)] + subcmd
    cmd = [sys.executable, str(native)] + subcmd
    if threads:
        cmd += ["--threads", str(threads)]
    return cmd


def _read_samplesheet(path: str) -> list[dict]:
    sep = "\t" if str(path).lower().endswith((".tsv", ".tab")) else ","
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter=sep))


def stage_sra_prep(row, outdir, threads):
    """可选：SRA 下载 + 转 fastq（prefetch -> fasterq-dump）。"""
    sample = row["sample"]
    srr = row.get("srr_id") or row.get("sra_id") or ""
    if not srr:
        return []
    base = Path(outdir) / "00_SRA"
    return [
        ("sra_prefetch", sample,
         _native_cmd("sra-tools", ["prefetch", "--srr-id", srr,
                                   "--output-dir", str(base)], threads)),
        ("sra_to_fastq", sample,
         _native_cmd("sra-tools", ["fasterq-dump", "--sra-file", str(base / f"{srr}/{srr}.sra"),
                                   "--output-dir", str(base), "--split-3"], threads)),
    ]


def stage_dorado(row, outdir, threads):
    """可选：fast5 -> fastq 碱基识别。"""
    sample = row["sample"]
    reads = row.get("input_file", "")
    if not reads:
        return []
    base = Path(outdir) / "00_BASECALL"
    fastq = base / f"{sample}.fastq"
    return [
        ("dorado_basecall", sample,
         _native_cmd("dorado", ["basecall", "--model", "rna004_130bps_sup@v5.1.0",
                                "--reads", reads, "--output", str(fastq),
                                "--emit-fastq"], threads)),
    ]


def stage_align(row, reference, outdir, threads):
    """minimap2 比对 -> BAM。"""
    sample = row["sample"]
    reads = row.get("input_file", "")
    if not reads:
        return []
    align_dir = Path(outdir) / "01_MINIMAP2_ALIGN" / sample
    return [
        ("minimap2_align", sample,
         _native_cmd("minimap2", ["align", "--reads", reads, "--reference", reference,
                                  "--outdir", str(align_dir), "--prefix", sample,
                                  "--bam", "--args", "-x splice -uf -k14"], threads)),
    ]


def stage_samtools_qc(row, outdir, threads):
    """BAM sort/index + flagstat。"""
    sample = row["sample"]
    align_dir = Path(outdir) / "01_MINIMAP2_ALIGN" / sample
    raw_bam = align_dir / f"{sample}.bam"
    sorted_bam = align_dir / f"{sample}.sorted.bam"
    flagstat_dir = Path(outdir) / "01_MINIMAP2_ALIGN" / "FLAGSTAT"
    flagstat_dir.mkdir(parents=True, exist_ok=True)
    return [
        ("samtools_sort", sample,
         _native_cmd("samtools", ["sort", str(raw_bam), "-o", str(sorted_bam)], threads)),
        ("samtools_index", sample,
         _native_cmd("samtools", ["index", str(sorted_bam)], threads)),
        ("samtools_flagstat", sample,
         _native_cmd("samtools", ["flagstat", str(sorted_bam)],
                     threads) + [">", str(flagstat_dir / f"{sample}.flagstat.txt")]),
    ]


def stage_flair(row, reference, gtf, outdir, threads):
    """FLAIR consensus：bam2bed12 -> annotate -> collapse。"""
    sample = row["sample"]
    reads = row.get("input_file", "")
    sorted_bam = Path(outdir) / "01_MINIMAP2_ALIGN" / sample / f"{sample}.sorted.bam"
    base = Path(outdir) / "02_FLAIR_CONSENSUS"
    bed12 = base / "BED12" / f"{sample}.bed12"
    annotated = base / "ANNOTATED_BED" / f"{sample}.annotated.bed"
    base.mkdir(parents=True, exist_ok=True)
    return [
        ("flair_bam2bed12", sample,
         _native_cmd("flair", ["bam2bed12", "--input", str(sorted_bam),
                               "--output", str(bed12)], threads)),
        ("flair_annotate", sample,
         _native_cmd("flair", ["annotate", "--input", str(bed12), "--gtf", gtf,
                               "--output", str(annotated)], threads)),
        ("flair_collapse", sample,
         _native_cmd("flair", ["collapse", "--input", str(annotated),
                               "--genome", reference, "--reads", reads,
                               "--prefix", str(base / "CONSENSUS_FASTA" / sample),
                               "--gtf", gtf, "--min-support", "3",
                               "--end-window", "100", "--intpriming-threshold", "30",
                               "--trust-ends", "--remove-internal-priming",
                               "--stringent", "--check-splice",
                               "--mm2-args", "-I8g,--MD", "--quiet"], threads)),
    ]


def stage_stringtie(row, gtf, outdir, threads):
    """StringTie 组装 + 坐标修复 + merge 合并。"""
    sample = row["sample"]
    sorted_bam = Path(outdir) / "01_MINIMAP2_ALIGN" / sample / f"{sample}.sorted.bam"
    base = Path(outdir) / "03_STRINGTIE"
    assembled = base / "ASSEMBLED_GTF" / f"{sample}.stringtie.gtf"
    fixed = base / "ASSEMBLED_GTF" / "FIXED_GTF" / f"{sample}.stringtie.fixed.gtf"
    steps = [
        ("stringtie_assemble", sample,
         _native_cmd("stringtie", ["assemble", "--bam", str(sorted_bam),
                                   "--gtf", gtf, "--output", str(assembled),
                                   "--label", sample, "--conservative",
                                   "--long-reads", "--min-transcript-len", "200"], threads)),
        ("stringtie_fix_gtf", sample,
         _native_cmd("stringtie", ["fix_gtf", "--gtf", str(assembled),
                                   "--output", str(fixed)], threads)),
    ]
    return steps


def stage_stringtie_merge(gtf, outdir, threads):
    """跨样本合并 GTF（单次执行）。"""
    base = Path(outdir) / "03_STRINGTIE"
    gtf_list = base / "GTF_LIST.txt"
    gtf_dir = base / "ASSEMBLED_GTF" / "FIXED_GTF"
    if gtf_dir.exists():
        files = sorted(gtf_dir.glob("*.fixed.gtf"))
        gtf_list.parent.mkdir(parents=True, exist_ok=True)
        gtf_list.write_text("\n".join(str(f) for f in files) + "\n", encoding="utf-8")
    merged = base / "MERGED_GTF" / "stringtie_merged_nonredundant.gtf"
    return [
        ("stringtie_merge", "",
         _native_cmd("stringtie", ["merge", "--gtf", gtf,
                                   "--gtf-list", str(gtf_list),
                                   "--output", str(merged),
                                   "--min-transcript-len", "200"], threads)),
    ]


def stage_orf(row, outdir, threads, orf_tool="transdecoder"):
    """ORF 预测：TransDecoder 或 TD2。"""
    sample = row["sample"]
    fasta = row.get("merged_fasta", "")
    if not fasta:
        # 缺省使用 FLAIR consensus FASTA
        fasta = str(Path(outdir) / "02_FLAIR_CONSENSUS" / "CONSENSUS_FASTA" / f"{sample}.flair.collapse.fasta")
    if orf_tool == "td2":
        base = Path(outdir) / "04_2_TD2_ORF_PREDICTION" / sample
        return [
            ("td2_longorfs", sample,
             _native_cmd("td2", ["longorfs", "--input", fasta,
                                 "--output-dir", str(base / "longorfs"),
                                 "--min-length", "90", "--genetic-code", "1",
                                 "--strand-specific", "--alt-start"], threads)),
            ("td2_predict", sample,
             _native_cmd("td2", ["predict", "--input", fasta,
                                 "--output-dir", str(base / "longorfs"),
                                 "--psauron-all-frame"], threads)),
        ]
    base = Path(outdir) / "04_1_TRANSDECODER_ORF_PREDICTION" / sample
    return [
        ("transdecoder_longorfs", sample,
         _native_cmd("transdecoder", ["longorfs", "--input", fasta,
                                      "--output-dir", str(base / "longorfs"),
                                      "--min-protein-length", "50",
                                      "--genetic-code", "Universal",
                                      "--strand-specific"], threads)),
        ("transdecoder_predict", sample,
         _native_cmd("transdecoder", ["predict", "--input", fasta,
                                      "--output-dir", str(base / "longorfs"),
                                      "--no-refine-starts"], threads)),
    ]


def plan_stages(args) -> list[tuple]:
    rows = _read_samplesheet(args.samplesheet)
    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    plan: list[tuple] = []
    for row in rows:
        if args.with_prep:
            plan += stage_sra_prep(row, args.outdir, args.threads)
        if args.with_dorado:
            plan += stage_dorado(row, args.outdir, args.threads)
        plan += stage_align(row, args.reference, args.outdir, args.threads)
        plan += stage_samtools_qc(row, args.outdir, args.threads)
        plan += stage_flair(row, args.reference, args.gtf, args.outdir, args.threads)
        plan += stage_stringtie(row, args.gtf, args.outdir, args.threads)
        plan += stage_orf(row, args.outdir, args.threads, args.orf_tool)
    plan += stage_stringtie_merge(args.gtf, args.outdir, args.threads)
    return plan


def main(argv=None):
    argv = list(argv) if argv is not None else sys.argv[1:]

    if "--list-stages" in argv:
        print(json.dumps({"id": "custom_nanoseq",
                          "stages": ["sra_prep", "dorado_basecall", "minimap2_align",
                                     "samtools_qc", "flair_consensus", "stringtie_assembly",
                                     "orf_prediction"]},
                         ensure_ascii=False, indent=2))
        return 0

    p = argparse.ArgumentParser(description="nanoseq — Nanopore RNA-seq 流程编排")
    p.add_argument("--samplesheet", required=True, help="样本表 CSV（sample,input_file,fasta,gtf 列）")
    p.add_argument("--reference", required=True, help="参考基因组 FASTA")
    p.add_argument("--gtf", required=True, help="参考注释 GTF")
    p.add_argument("--orf-tool", choices=("transdecoder", "td2"), default="transdecoder")
    p.add_argument("--with-prep", action="store_true", help="启用 SRA 下载前置")
    p.add_argument("--with-dorado", action="store_true", help="启用 dorado 碱基识别前置")
    p.add_argument("--outdir", default="results")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--dry-run", action="store_true", default=True, help="仅打印命令（默认）")
    p.add_argument("--real", action="store_true", help="真实执行 modules/<sw>/native/main.py")
    p.add_argument("--list-stages", action="store_true")
    args = p.parse_args(argv)

    mode = "real" if args.real else "dry-run"
    print(f"# custom_nanoseq ({mode}) orf_tool={args.orf_tool}")
    plan = plan_stages(args)
    if not plan:
        print("[WARN] samplesheet 未产生任何可执行 stage（检查 sample/input_file 列）")
        return 0

    executed = 0
    for stage, sample, cmd in plan:
        label = f"[{stage}]" + (f" {sample}" if sample else "")
        print(f"{label}: " + " ".join(map(str, cmd)))
        if args.real:
            if isinstance(cmd, list) and cmd and cmd[0] == "<MISSING>":
                print(f"  [SKIP] 缺少 {cmd[1]}，跳过执行")
                continue
            # 允许命令中出现重定向
            if ">" in [str(c) for c in cmd]:
                import shlex
                subprocess.run(" ".join(map(str, cmd)), shell=True, check=True)
            else:
                subprocess.run(cmd, check=True)
            executed += 1
    if args.real:
        print(f"# 已执行 {executed} 个命令")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
