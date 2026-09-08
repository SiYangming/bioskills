#!/usr/bin/env python3
"""sratools_pipeline: SRA 批量获取组合编排（prefetch -> fasterq-dump/fastq-dump）

按「subworkflow/ 组合 = 可复用跨样本固定套路」形态提供 SRA 数据库批量下载 + 转 FASTQ 的阶段编排。
两阶段（见同级 meta.yaml stages）：
  sra_prefetch  逐 accession 委托 modules/sra-tools/native/main.py prefetch（-O <download_dir>）
  sra_to_fastq  逐 .sra 委托 modules/sra-tools/native/main.py fasterq-dump / fastq-dump
                （--split-3 --gzip -O <fastq_dir>；fasterq-dump 为官方推荐高速版）

可执行三种模式（与 subworkflow/fastp_bwa_samtools、umi_tools_extract_dedup 一致）：
  a) --list-stages：列出 stages（不依赖必填参数）
  b) --dry-run（默认）：逐 accession 构造并打印委托命令，不真正执行
  c) --real：真实执行（需 sra-tools 已安装、网络可达、输入文件存在）

批量一体化 + 状态管理（download|convert|status|stop|clean、锁/PID/失败记录）仍由经典脚本
native/sra_pipeline.sh 提供（本编排打印的命令形态与其语义一致）。
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent.parent.parent          # 仓库根（subworkflow/<x>/native -> 上三级）
_SRA_NATIVE = _ROOT / "modules" / "sra-tools" / "native" / "main.py"
_STAGES = ["sra_prefetch", "sra_to_fastq"]


def _read_srr_list(path: str) -> list[str]:
    """读取 SRR/accession 列表（每行一个；跳过空行与 # 注释行）。"""
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"[ERROR] SRR 列表不存在: {p}")
    ids = [
        ln.strip() for ln in p.read_text().splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]
    if not ids:
        raise SystemExit(f"[ERROR] SRR 列表为空: {p}")
    return ids


def _native(sub: list[str], threads: int, tmpdir: str | None = None) -> list[str]:
    """构造 modules/sra-tools/native/main.py 的委托命令。"""
    if not _SRA_NATIVE.exists():
        return ["<MISSING>", str(_SRA_NATIVE)] + sub
    cmd = [sys.executable, str(_SRA_NATIVE)] + sub
    cmd += ["--threads", str(threads)]
    if tmpdir:
        cmd += ["--tmpdir", str(tmpdir)]
    return cmd


def stage_prefetch(a: argparse.Namespace) -> list[tuple[str, list[str]]]:
    """sra_prefetch：逐 accession 委托 prefetch，输出 <download_dir>/<srr_id>/<srr_id>.sra。"""
    download = Path(a.download_dir)
    download.mkdir(parents=True, exist_ok=True)
    tasks: list[tuple[str, list[str]]] = []
    for srr in _read_srr_list(a.srr_list):
        sub = ["prefetch", srr, "-O", str(download)]
        if a.prefetch_options:
            sub += ["--prefetch-options", a.prefetch_options]
        tasks.append((f"sra_prefetch:{srr}", _native(sub, a.threads)))
    return tasks


def stage_dump(a: argparse.Namespace) -> list[tuple[str, list[str]]]:
    """sra_to_fastq：逐 .sra 委托 fasterq-dump / fastq-dump（--split-3 --gzip）。"""
    fastq = Path(a.fastq_dir)
    fastq.mkdir(parents=True, exist_ok=True)
    tasks: list[tuple[str, list[str]]] = []
    for srr in _read_srr_list(a.srr_list):
        sra_file = Path(a.download_dir) / srr / f"{srr}.sra"
        sub = [a.dump_method, str(sra_file), "-O", str(fastq)]
        if a.split_3:
            sub.append("--split-3")
        if a.gzip:
            sub.append("--gzip")
        if not sra_file.exists():
            # dry-run 阶段 prefetch 尚未执行；--real 前请先完成 prefetch 阶段
            print(f"  [warn] 未找到 {sra_file}（--real 前请先完成 prefetch）", file=sys.stderr)
        tasks.append((f"sra_to_fastq:{srr}", _native(sub, a.threads, a.tmpdir)))
    return tasks


def main(argv=None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]

    if "--list-stages" in argv:
        print(json.dumps({"id": "custom_sratools_pipeline", "stages": _STAGES},
                         ensure_ascii=False, indent=2))
        return 0

    p = argparse.ArgumentParser(
        prog="sratools-pipeline-skill",
        description="subworkflow/sratools_pipeline — SRA 批量获取编排（prefetch -> fasterq-dump/fastq-dump）",
    )
    p.add_argument("--srr-list", required=True,
                   help="SRA accession 列表文件（每行一个；支持 # 注释与空行）")
    p.add_argument("--download-dir", default="sra_downloads", help="prefetch 下载目录")
    p.add_argument("--fastq-dir", default="fastq_files", help="FASTQ 输出目录")
    p.add_argument("--dump-method", choices=("fasterq-dump", "fastq-dump"),
                   default="fasterq-dump", help="转 FASTQ 工具（默认官方推荐 fasterq-dump）")
    p.add_argument("--split-3", dest="split_3", action="store_true", help="双端拆分 *_1/*_2（默认开启）")
    p.add_argument("--no-split-3", dest="split_3", action="store_false", help="关闭 --split-3")
    p.add_argument("--gzip", dest="gzip", action="store_true", help="输出 .fastq.gz（默认开启）")
    p.add_argument("--no-gzip", dest="gzip", action="store_false", help="关闭 --gzip")
    p.add_argument("--prefetch-options", default="-f yes -t http",
                   help="prefetch 附加选项（默认 '-f yes -t http'）")
    p.add_argument("--tmpdir", default="/tmp", help="fasterq-dump 临时目录（-t）")
    p.add_argument("--threads", type=int, default=4)
    p.add_argument("--dry-run", action="store_true", default=True, help="仅打印命令（默认）")
    p.add_argument("--real", action="store_true",
                   help="真实执行 modules/sra-tools/native/main.py（需先安装 sra-tools）")
    p.set_defaults(split_3=True, gzip=True)
    args = p.parse_args(argv)

    mode = "real" if args.real else "dry-run"
    print(f"# custom_sratools_pipeline ({mode}) srr_list={args.srr_list} "
          f"dump_method={args.dump_method} threads={args.threads}")

    tasks = stage_prefetch(args) + stage_dump(args)
    for name, cmd in tasks:
        print(f"[{name}]: " + " ".join(map(str, cmd)))
        if args.real and not (isinstance(cmd, list) and cmd and cmd[0] == "<MISSING>"):
            subprocess.run(cmd, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
