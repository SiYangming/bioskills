#!/usr/bin/env python3
"""custom/flrnaseq: 全长 RNA-seq ORF 预测流程编排器。

流程（迁移自 snakemake.smk/flrnaseq.smk）：
  transdecoder longorfs -> transdecoder predict
  td2 longorfs -> td2 predict
  orffinder run（可选第三路线）

执行模式：
  a) --dry-run：仅打印每个 stage 的命令（默认）
  b) --real：真实调用 skills/<sw>/native/main.py（需对应工具已安装）
  c) --list-stages：按 meta.yaml 列出 stages

编排原则：只做流程串联，每个 step 委托给 skills/<sw>/native/main.py。
"""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent  # skills/


def _native_cmd(software: str, subcmd: list[str], threads: int | None = None) -> list[str]:
    native = _SKILLS_ROOT / software / "native" / "main.py"
    if not native.exists():
        return ["<MISSING>", str(native)] + subcmd
    cmd = [sys.executable, str(native)] + subcmd
    if threads:
        cmd += ["--threads", str(threads)]
    return cmd


def _read_samplesheet(path: str) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def stage_transdecoder(row, outdir, threads):
    """TransDecoder.LongOrfs -> TransDecoder.Predict（输出 pep/cds/gff3/bed）。"""
    sample = row["sample"]
    fasta = row.get("long_read_fasta", row.get("seq_data", ""))
    base = Path(outdir) / "01_1_TRANSDECODER" / sample
    steps = [
        ("transdecoder_longorfs", sample,
         _native_cmd("transdecoder", ["longorfs", "--input", fasta,
                                      "--output-dir", str(base / "longorfs"),
                                      "--min-protein-length", "50",
                                      "--genetic-code", "Universal",
                                      "--strand-specific", "--complete-orfs-only"], threads)),
        ("transdecoder_predict", sample,
         _native_cmd("transdecoder", ["predict", "--input", fasta,
                                      "--output-dir", str(base / "longorfs"),
                                      "--no-refine-starts"], threads)),
    ]
    return steps


def stage_td2(row, outdir, threads):
    """TD2.LongOrfs -> TD2.Predict（输出 pep/cds/gff3/bed）。"""
    sample = row["sample"]
    fasta = row.get("long_read_fasta", row.get("seq_data", ""))
    base = Path(outdir) / "01_2_TD2" / sample
    steps = [
        ("td2_longorfs", sample,
         _native_cmd("td2", ["longorfs", "--input", fasta,
                             "--output-dir", str(base / "longorfs"),
                             "--min-length", "90", "--abs-min-length", "90",
                             "--genetic-code", "1", "--strand-specific",
                             "--alt-start", "--all-stopless"], threads)),
        ("td2_predict", sample,
         _native_cmd("td2", ["predict", "--input", fasta,
                             "--output-dir", str(base / "longorfs"),
                             "--psauron-all-frame"], threads)),
    ]
    return steps


def stage_orffinder(row, outdir, threads):
    """NCBI ORFfinder（outfmt=2 文本 ASN.1，默认）。"""
    sample = row["sample"]
    fasta = row.get("long_read_fasta", row.get("seq_data", ""))
    outdir_path = Path(outdir) / "03_ORFFINDER"
    outdir_path.mkdir(parents=True, exist_ok=True)
    steps = [
        ("orffinder", sample,
         _native_cmd("orffinder", ["run", "--input", fasta,
                                   "--output", str(outdir_path / f"{sample}.asn1"),
                                   "--outfmt", "2",
                                   "--start-codon", "2", "--min-length", "30"], threads)),
    ]
    return steps


def plan_stages(args) -> list[tuple]:
    rows = _read_samplesheet(args.samplesheet)
    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    plan: list[tuple] = []
    for row in rows:
        plan += stage_transdecoder(row, args.outdir, args.threads)
        plan += stage_td2(row, args.outdir, args.threads)
        plan += stage_orffinder(row, args.outdir, args.threads)
    return plan


def main(argv=None):
    argv = list(argv) if argv is not None else sys.argv[1:]

    if "--list-stages" in argv:
        print(json.dumps({"id": "custom_flrnaseq",
                          "stages": ["transdecoder_longorfs", "transdecoder_predict",
                                     "td2_longorfs", "td2_predict", "orffinder"]},
                         ensure_ascii=False, indent=2))
        return 0

    p = argparse.ArgumentParser(description="custom/flrnaseq — 全长 RNA-seq ORF 预测流程编排")
    p.add_argument("--samplesheet", required=True, help="样本表 CSV（含 sample 与 long_read_fasta 列）")
    p.add_argument("--outdir", default="results")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--dry-run", action="store_true", default=True, help="仅打印命令（默认）")
    p.add_argument("--real", action="store_true", help="真实执行 skills/<sw>/native/main.py")
    p.add_argument("--list-stages", action="store_true")
    args = p.parse_args(argv)

    mode = "real" if args.real else "dry-run"
    print(f"# custom_flrnaseq ({mode})")
    plan = plan_stages(args)
    if not plan:
        print("[WARN] samplesheet 未产生任何可执行 stage（检查 sample / long_read_fasta 列）")
        return 0

    executed = 0
    for stage, sample, cmd in plan:
        print(f"[{stage}] {sample}: " + " ".join(map(str, cmd)))
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
