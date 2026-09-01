#!/usr/bin/env python3
"""isoseq: PacBio Iso-Seq 全长转录组流程编排器。

将原 /snakemake.smk/isoseq.smk 单体流程拆分为原子模块后重新编排：
  pbccs -> lima -> isoseq3 refine -> bamtools convert -> gstama polyA 清理
  -> minimap2 / uLTRA 比对 -> gstama collapse -> gstama filelist -> gstama merge

执行模式：
  a) --dry-run：仅打印每个 stage 将调用的命令（默认）
  b) --real：真实调用 modules/<sw>/native/main.py（需对应工具已安装）
  c) --list-stages：按 meta.yaml 列出 stages

编排原则：本脚本只做「流程串联」，每个 step 一律委托给 modules/<sw>/native/main.py，
不重复实现任何工具命令逻辑。
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
_DEFAULT_DIRS = {
    "pbccs": "01PBCCS",
    "lima": "02LIMA",
    "refine": "03ISOSEQ_REFINE",
    "bamtools": "04BAMTOOLS_CONVERT",
    "polya": "05TAMA_POLYACLEANUP",
    "mapping": "06_{aligner}",
    "collapse": "07TAMA_COLLAPSE",
    "filelist": "08TAMA_FILELIST",
    "merge": "09TAMA_MERGE",
}


def _native_cmd(software: str, subcmd: list[str], threads: int | None = None) -> list[str]:
    """构造 modules/<sw>/native/main.py 的调用命令。"""
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


def _split_chunk_nums(chunk_total: int) -> list[int]:
    return list(range(1, chunk_total + 1))


def stage_pbccs(row, primers, outdir, chunk_total, threads):
    """subreads -> HiFi CCS（按 chunk 并行）。"""
    sample = row["sample"]
    seq = row.get("seq_data", "")
    start = row.get("start_from", "").strip().lower()
    if not seq or start not in ("", "ccs"):
        return []
    base = Path(outdir) / _DEFAULT_DIRS["pbccs"] / sample
    steps = []
    for n in _split_chunk_nums(chunk_total):
        sub = [
            "ccs",
            "--input", seq,
            "--outdir", str(base),
            "--chunk-num", str(n),
            "--chunk-total", str(chunk_total),
        ]
        steps.append(("pbccs", sample, n, _native_cmd("pbccs", sub, threads)))
    return steps


def stage_lima(row, primers, outdir, chunk_total, threads):
    """CCS -> 引物去除 / 条形码拆分。"""
    sample = row["sample"]
    seq = row.get("seq_data", "")
    start = row.get("start_from", "").strip().lower()
    base = Path(outdir) / _DEFAULT_DIRS["lima"] / sample
    steps = []
    if start in ("", "ccs"):
        # 输入来自 pbccs 分块输出
        for n in _split_chunk_nums(chunk_total):
            reads = Path(outdir) / _DEFAULT_DIRS["pbccs"] / sample / f"{sample}.chunk{n}.bam"
            sub = ["lima", "--reads", str(reads), "--primers", primers,
                   "--outdir", str(base), "--prefix", f"{sample}.chunk{n}",
                   "--isoseq", "--peek-guess"]
            steps.append(("lima", sample, n, _native_cmd("lima", sub, threads)))
    elif start == "lima":
        for n in _split_chunk_nums(chunk_total):
            sub = ["lima", "--reads", seq, "--primers", primers,
                   "--outdir", str(base), "--prefix", f"{sample}.chunk{n}",
                   "--isoseq", "--peek-guess"]
            steps.append(("lima", sample, n, _native_cmd("lima", sub, threads)))
    return steps


def stage_refine(row, primers, outdir, chunk_total, threads):
    """lima 产物 -> isoseq3 refine（polyA / 接头去除）。"""
    sample = row["sample"]
    start = row.get("start_from", "").strip().lower()
    base = Path(outdir) / _DEFAULT_DIRS["refine"] / sample
    steps = []
    if start in ("", "ccs", "lima"):
        for n in _split_chunk_nums(chunk_total):
            bam = Path(outdir) / _DEFAULT_DIRS["lima"] / sample / f"{sample}.chunk{n}.bam"
            sub = ["refine", "--bam", str(bam), "--primers", primers,
                   "--outdir", str(base), "--prefix", f"{sample}.chunk{n}"]
            steps.append(("isoseq3_refine", sample, n, _native_cmd("isoseq3", sub, threads)))
    elif start == "refine":
        for n in _split_chunk_nums(chunk_total):
            sub = ["refine", "--bam", row.get("seq_data", ""), "--primers", primers,
                   "--outdir", str(base), "--prefix", f"{sample}.chunk{n}"]
            steps.append(("isoseq3_refine", sample, n, _native_cmd("isoseq3", sub, threads)))
    return steps


def stage_bamtools(row, outdir, chunk_total, threads):
    """refined BAM -> FASTA。"""
    sample = row["sample"]
    start = row.get("start_from", "").strip().lower()
    base = Path(outdir) / _DEFAULT_DIRS["bamtools"] / sample
    steps = []
    if start in ("", "ccs", "lima", "refine"):
        for n in _split_chunk_nums(chunk_total):
            bam = Path(outdir) / _DEFAULT_DIRS["refine"] / sample / f"{sample}.chunk{n}.bam"
            sub = ["convert", "--bam", str(bam), "--outdir", str(base),
                   "--format", "fasta", "--prefix", f"{sample}.chunk{n}"]
            steps.append(("bamtools_convert", sample, n, _native_cmd("bamtools", sub, threads)))
    elif start == "bamtools":
        for n in _split_chunk_nums(chunk_total):
            sub = ["convert", "--bam", seq, "--outdir", str(base),
                   "--format", "fasta", "--prefix", f"{sample}.chunk{n}"]
            steps.append(("bamtools_convert", sample, n, _native_cmd("bamtools", sub, threads)))
    return steps


def stage_polya(row, outdir, chunk_total, threads):
    """FASTA -> TAMA FLNC polyA 清理。"""
    sample = row["sample"]
    start = row.get("start_from", "").strip().lower()
    base = Path(outdir) / _DEFAULT_DIRS["polya"] / sample
    steps = []
    if start in ("", "ccs", "lima", "refine", "bamtools"):
        for n in _split_chunk_nums(chunk_total):
            fasta = Path(outdir) / _DEFAULT_DIRS["bamtools"] / sample / f"{sample}.chunk{n}.fasta"
            sub = ["polyacleanup", "--fasta", str(fasta), "--outdir", str(base),
                   "--prefix", f"{sample}.chunk{n}"]
            steps.append(("gstama_polyacleanup", sample, n, _native_cmd("gstama", sub, threads)))
    elif start == "gstama":
        for n in _split_chunk_nums(chunk_total):
            sub = ["polyacleanup", "--fasta", seq, "--outdir", str(base),
                   "--prefix", f"{sample}.chunk{n}"]
            steps.append(("gstama_polyacleanup", sample, n, _native_cmd("gstama", sub, threads)))
    return steps


def stage_mapping(row, reference, gtf, outdir, chunk_total, threads, aligner):
    """polyA 清理产物 -> minimap2 / uLTRA 比对（BAM）。"""
    sample = row["sample"]
    start = row.get("start_from", "").strip().lower()
    mapping_dir = _DEFAULT_DIRS["mapping"].format(aligner=aligner)
    base = Path(outdir) / mapping_dir / sample
    steps = []
    if start in ("", "ccs", "lima", "refine", "bamtools", "gstama"):
        for n in _split_chunk_nums(chunk_total):
            reads = Path(outdir) / _DEFAULT_DIRS["polya"] / sample / f"{sample}.chunk{n}_gstama.fa.gz"
            if aligner == "ultra":
                # uLTRA: 先建索引（每物种一次，此处按 sample 简化），再比对
                sub = ["align", "--reads", str(reads), "--genome", reference,
                       "--index-dir", str(Path(outdir) / "INDEX"), "--outdir", str(base),
                       "--prefix", f"{sample}.chunk{n}"]
                steps.append(("ultra_align", sample, n, _native_cmd("ultra", sub, threads)))
            else:
                sub = ["align", "--reads", str(reads), "--reference", reference,
                       "--outdir", str(base), "--prefix", f"{sample}.chunk{n}",
                       "--bam", "--args", "-x splice -uf -k14"]
                steps.append(("minimap2_align", sample, n, _native_cmd("minimap2", sub, threads)))
    elif start == "mapping":
        for n in _split_chunk_nums(chunk_total):
            if aligner == "ultra":
                sub = ["align", "--reads", row.get("seq_data", ""), "--genome", reference,
                       "--index-dir", str(Path(outdir) / "INDEX"), "--outdir", str(base),
                       "--prefix", f"{sample}.chunk{n}"]
                steps.append(("ultra_align", sample, n, _native_cmd("ultra", sub, threads)))
            else:
                sub = ["align", "--reads", row.get("seq_data", ""), "--reference", reference,
                       "--outdir", str(base), "--prefix", f"{sample}.chunk{n}",
                       "--bam", "--args", "-x splice -uf -k14"]
                steps.append(("minimap2_align", sample, n, _native_cmd("minimap2", sub, threads)))
    return steps


def stage_collapse(row, reference, outdir, chunk_total, threads, aligner):
    """比对 BAM -> gstama collapse（转录本去冗余，产出 bed）。"""
    sample = row["sample"]
    start = row.get("start_from", "").strip().lower()
    mapping_dir = _DEFAULT_DIRS["mapping"].format(aligner=aligner)
    base = Path(outdir) / _DEFAULT_DIRS["collapse"] / aligner / sample
    steps = []
    if start in ("", "ccs", "lima", "refine", "bamtools", "gstama", "mapping"):
        for n in _split_chunk_nums(chunk_total):
            bam = Path(outdir) / mapping_dir / sample / f"{sample}.chunk{n}.bam"
            sub = ["collapse", "--bam", str(bam), "--fasta", reference,
                   "--outdir", str(base), "--prefix", f"{sample}.chunk{n}",
                   "--args", "-x no_cap -a 100 -z 100 -sj sj_priority -sjt 20 -lde 5"]
            steps.append(("gstama_collapse", sample, n, _native_cmd("gstama", sub, threads)))
    return steps


def stage_filelist(samples, outdir, aligner, threads):
    """收集全部 collapse bed -> filelist.tsv。"""
    collapse_dir = Path(outdir) / _DEFAULT_DIRS["collapse"]
    filelist_dir = Path(outdir) / _DEFAULT_DIRS["filelist"]
    filelist_dir.mkdir(parents=True, exist_ok=True)
    sub = ["filelist", "--bed-dir", str(collapse_dir), "--outdir", str(filelist_dir),
           "--prefix", "filelist", "--pattern", "**/*.bed"]
    return [("gstama_filelist", "", 0, _native_cmd("gstama", sub, threads))]


def stage_merge(outdir, threads):
    """filelist.tsv -> merged.bed。"""
    merge_dir = Path(outdir) / _DEFAULT_DIRS["merge"]
    merge_dir.mkdir(parents=True, exist_ok=True)
    filelist = Path(outdir) / _DEFAULT_DIRS["filelist"] / "filelist.tsv"
    sub = ["merge", "--filelist", str(filelist), "--outdir", str(merge_dir),
           "--prefix", "merged"]
    return [("gstama_merge", "", 0, _native_cmd("gstama", sub, threads))]


def plan_stages(args) -> list[tuple]:
    """按 meta.yaml 的 stages 顺序生成全部 (stage, sample, n, cmd)。"""
    rows = _read_samplesheet(args.samplesheet)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    plan: list[tuple] = []
    for row in rows:
        plan += stage_pbccs(row, args.primers, outdir, args.chunk_total, args.threads)
        plan += stage_lima(row, args.primers, outdir, args.chunk_total, args.threads)
        plan += stage_refine(row, args.primers, outdir, args.chunk_total, args.threads)
        plan += stage_bamtools(row, outdir, args.chunk_total, args.threads)
        plan += stage_polya(row, outdir, args.chunk_total, args.threads)
        plan += stage_mapping(row, args.reference, args.gtf, outdir,
                              args.chunk_total, args.threads, args.aligner)
        plan += stage_collapse(row, args.reference, outdir, args.chunk_total,
                               args.threads, args.aligner)
    plan += stage_filelist(rows, outdir, args.aligner, args.threads)
    plan += stage_merge(outdir, args.threads)
    return plan


def main(argv=None):
    argv = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖必填参数）
    if "--list-stages" in argv:
        print(json.dumps({"id": "custom_isoseq",
                          "stages": ["pbccs", "lima", "isoseq3_refine", "bamtools_convert",
                                     "gstama_polyacleanup", "minimap2_align/ultra_align",
                                     "gstama_collapse", "gstama_filelist", "gstama_merge"]},
                         ensure_ascii=False, indent=2))
        return 0

    p = argparse.ArgumentParser(description="isoseq — PacBio Iso-Seq 全长转录组流程编排")
    p.add_argument("--samplesheet", required=True, help="样本表 CSV/TSV（含 sample；可选 seq_data/start_from）")
    p.add_argument("--primers", required=True, help="引物 FASTA（lima / isoseq3 refine）")
    p.add_argument("--reference", required=True, help="参考基因组 FASTA")
    p.add_argument("--gtf", help="参考注释 GTF（仅 ultra 路径需要）")
    p.add_argument("--aligner", choices=("minimap2", "ultra"), default="minimap2")
    p.add_argument("--outdir", default="results")
    p.add_argument("--chunk-total", type=int, default=10, help="pbccs 分块总数")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--dry-run", action="store_true", default=True, help="仅打印命令（默认）")
    p.add_argument("--real", action="store_true", help="真实执行 modules/<sw>/native/main.py")
    p.add_argument("--list-stages", action="store_true")
    args = p.parse_args(argv)

    mode = "real" if args.real else "dry-run"
    print(f"# custom_isoseq ({mode}) aligner={args.aligner} chunks={args.chunk_total}")
    plan = plan_stages(args)
    if not plan:
        print("[WARN] samplesheet 未产生任何可执行 stage（检查 sample/seq_data/start_from 列）")
        return 0

    executed = 0
    for stage, sample, n, cmd in plan:
        label = f"[{stage}]" + (f" {sample}" if sample else "") + (f" chunk{n}" if n else "")
        print(f"{label}: " + " ".join(map(str, cmd)))
        if args.real:
            if isinstance(cmd, list) and cmd and cmd[0] == "<MISSING>":
                print(f"  [SKIP] 缺少 {cmd[1]}，跳过执行")
                continue
            subprocess.run(cmd, check=True)
            executed += 1
    if args.real:
        print(f"# 已执行 {executed} 个命令")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
