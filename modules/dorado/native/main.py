#!/usr/bin/env python3
"""dorado native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py basecall rna004_130bps_sup@v5.1.0 pod5_dir/ --output-dir out --emit-fastq --threads 8
   python main.py demux reads.fastq --kit-name SQK-RNA004-24 --output-dir demux_out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑提炼自 snakemake.smk/nanoseq.smk/config/config.yaml 的 dorado 段
（model: rna004_130bps_sup@v5.1.0；enable_dorado 开关）与 dorado 官方用法：
  basecall  dorado basecaller <model> <reads> --emit-fastq [--output-dir] [--device] [--num-workers]
  demux     dorado demux <reads> [--kit-name] [--output-dir]
所有子命令自动注入线程（--num-workers）与临时目录优化。
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

# nanoseq config.yaml 的 dorado 默认模型（RNA direct RNA-seq）
DEFAULT_RNA_MODEL = "rna004_130bps_sup@v5.1.0"

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "basecall": "raw 信号（POD5/FAST5）-> FASTQ（dorado basecaller，--emit-fastq）",
    "demux": "FASTQ -> barcode 拆分（dorado demux，按 --kit-name）",
}


class DoradoSkill(base.SkillBase):
    software = "dorado"
    binary = "dorado"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 dorado 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary]
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "basecall":
            cmd.append("basecaller")
            model = kw.get("model")
            if not model:
                model = DEFAULT_RNA_MODEL  # nanoseq config 默认 RNA 模型
            reads = kw.get("reads")
            if not reads:
                raise ValueError("basecall 缺少必填参数 reads（POD5/FAST5 目录或文件）")
            cmd += [str(model), str(reads)]
            # nanoseq：--emit-fastq 输出 FASTQ（默认开启，可用 --no-emit-fastq 关闭）
            if kw.get("emit_fastq", True):
                cmd.append("--emit-fastq")
            outdir = kw.get("output") or kw.get("output_dir")
            if outdir:
                cmd += ["--output-dir", str(outdir)]
            device = kw.get("device")
            if device:
                cmd += ["--device", str(device)]
            cmd += ["--num-workers", str(threads)]

        elif subcommand == "demux":
            cmd.append("demux")
            reads = kw.get("reads")
            if not reads:
                raise ValueError("demux 缺少必填参数 reads（FASTQ 文件）")
            cmd.append(str(reads))
            outdir = kw.get("output") or kw.get("output_dir")
            if outdir:
                cmd += ["--output-dir", str(outdir)]
            kit = kw.get("demux_kit") or kw.get("kit_name")
            if kit:
                cmd += ["--kit-name", str(kit)]
            if kw.get("emit_fastq"):
                cmd.append("--emit-fastq")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dorado-skill",
        description="dorado native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # basecall
    pb = sub.add_parser("basecall", help=SUBCOMMANDS["basecall"])
    pb.add_argument("model", nargs="?", help=f"模型名/目录（默认 {DEFAULT_RNA_MODEL}）")
    pb.add_argument("reads", help="输入 POD5/FAST5 目录或文件")
    pb.add_argument("--output-dir", "-o", dest="output", help="输出目录")
    pb.add_argument("--emit-fastq", dest="emit_fastq", action="store_true", help="输出 FASTQ（默认开启，见 --no-emit-fastq）")
    pb.add_argument("--no-emit-fastq", dest="emit_fastq", action="store_false", help="关闭 --emit-fastq")
    pb.add_argument("--device", help="计算设备（cuda:all / cuda:0 / cpu）")
    pb.add_argument("--extra-args", help="透传给 dorado 的额外参数")
    _add_runtime_opts(pb)

    # demux
    pd = sub.add_parser("demux", help=SUBCOMMANDS["demux"])
    pd.add_argument("reads", help="输入 FASTQ 文件")
    pd.add_argument("--output-dir", "-o", dest="output", help="输出目录")
    pd.add_argument("--kit-name", help="barcode 试剂盒名（如 SQK-RNA004-24）")
    pd.add_argument("--emit-fastq", action="store_true", help="输出 FASTQ")
    pd.add_argument("--extra-args", help="透传给 dorado 的额外参数")
    _add_runtime_opts(pd)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = DoradoSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = DoradoSkill()
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

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
