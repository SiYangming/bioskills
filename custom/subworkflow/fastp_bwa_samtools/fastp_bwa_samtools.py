#!/usr/bin/env python3
"""fastp_bwa_samtools: 最小复合流程骨架（fastp -> bwa-mem2 mem -> samtools sort/index）

可执行三种模式：
  a) --dry-run：仅打印 stage 命令（默认，避免依赖缺失）
  b) --real：真的调用 skills/<sw>/native/main.py（需对应 native 构建完成）
  c) --list-stages：按 meta.yaml 列出 stages

当前版本的目的是**演示 custom/ 复合流程如何存档与调用原子技能**，不是真的跑完整 pipeline。
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent.parent / "skills"  # skills/
_STAGES = ["fastp", "bwa-mem2", "samtools", "qc_optional"]


def _stage_cmd(software: str, subcmd: list[str], threads: int) -> list[str]:
    """按 skills/<sw>/native/main.py 形式构造命令列表。"""
    native = _SKILLS_ROOT / software / "native" / "main.py"
    if not native.exists():
        return ["<MISSING>", str(native)] + subcmd
    return [sys.executable, str(native)] + subcmd + ["--threads", str(threads)]


def stage_fastp(sample_id, r1, r2, outdir, threads):
    fastp_out = Path(outdir) / "fastp"
    fastp_out.mkdir(parents=True, exist_ok=True)
    sub = [
        "run",
        "-i", r1,
        *(["-I", r2] if r2 else []),
        "-o", str(fastp_out / f"{sample_id}_R1.clean.fq.gz"),
        *(["-O", str(fastp_out / f"{sample_id}_R2.clean.fq.gz")] if r2 else []),
        "-h", str(fastp_out / f"{sample_id}_fastp.html"),
        "-j", str(fastp_out / f"{sample_id}_fastp.json"),
    ]
    return ("fastp", _stage_cmd("fastp", sub, threads))


def stage_bwa_mem2(sample_id, r1, r2, ref, outdir, threads):
    bam_out = Path(outdir) / "bam"
    bam_out.mkdir(parents=True, exist_ok=True)
    # bwa-mem2 mem -> samtools view -> samtools sort
    sub = [
        "mem", "-R", f"@RG\\tID:{sample_id}\\tSM:{sample_id}\\tLB:{sample_id}",
        ref, r1,
    ]
    if r2:
        sub.append(r2)
    # bwa-mem2 输出 SAM，这里在执行态管道给 samtools view -O BAM（dry-run 打印即可）
    return ("bwa-mem2", _stage_cmd("bwa-mem2", sub, threads) + ["|", "samtools", "view", "-O", "BAM", "-o", str(bam_out / f"{sample_id}.bam")])


def stage_samtools(sample_id, outdir, threads):
    bam_out = Path(outdir) / "bam"
    raw = bam_out / f"{sample_id}.bam"
    sorted_bam = bam_out / f"{sample_id}.sorted.bam"
    sort_cmd = _stage_cmd("samtools", ["sort", str(raw), "-o", str(sorted_bam)], threads)
    index_cmd = _stage_cmd("samtools", ["index", str(sorted_bam)], threads)
    return ("samtools", [sort_cmd, index_cmd])


def run_stages(args, real: bool):
    tasks = [
        stage_fastp(args.sample_id, args.reads_r1, args.reads_r2, args.outdir, args.threads),
        stage_bwa_mem2(args.sample_id, args.reads_r1, args.reads_r2, args.reference, args.outdir, args.threads),
        stage_samtools(args.sample_id, args.outdir, args.threads),
    ]
    for name, cmd in tasks:
        if isinstance(cmd, list) and cmd and isinstance(cmd[0], list):
            # samtools 有两步
            for i, c in enumerate(cmd, 1):
                print(f"[{name}] #{i}: " + " ".join(map(str, c)))
                if real:
                    subprocess.run(c, check=True)
        else:
            print(f"[{name}]: " + " ".join(map(str, cmd)))
            if real and not (isinstance(cmd, list) and cmd and cmd[0] == "<MISSING>"):
                subprocess.run(cmd, check=True)


def main(argv=None):
    p = argparse.ArgumentParser(description="custom/fastp_bwa_samtools — 最小复合流程骨架")
    p.add_argument("--sample-id", required=True)
    p.add_argument("--reads-r1", required=True)
    p.add_argument("--reads-r2")
    p.add_argument("--reference", required=True)
    p.add_argument("--outdir", default="results")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--dry-run", action="store_true", default=True, help="仅打印命令（默认）")
    p.add_argument("--real", action="store_true", help="真实执行 skills/<sw>/native/main.py（需先构建对应软件）")
    p.add_argument("--list-stages", action="store_true")
    args = p.parse_args(argv)

    if args.list_stages:
        print(json.dumps({"id": "custom_fastp_bwa_samtools", "stages": _STAGES}, ensure_ascii=False, indent=2))
        return 0

    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    mode = "real" if args.real else "dry-run"
    print(f"# custom_fastp_bwa_samtools ({mode}) sample={args.sample_id}")
    run_stages(args, real=args.real)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
