#!/usr/bin/env python3
"""pbccs native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py ccs --subreads sample.subreads.bam --outdir out --chunk-num 1 --chunk-total 2 --threads 8
   python main.py ccs sample.subreads.bam out/ccs.chunk1.bam --chunk 1/2 --min-rq 0.95
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/ccs_analysis.py
与 workflow/rules/pbccs.smk：ccs <in> <out> --report-file --report-json --metrics-json
--chunk N/TOTAL --min-rq --min-passes --min-snr --min-length --max-length --top-passes -j。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 skills/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "ccs": "subreads BAM -> HiFi/CCS BAM（分块一致性序列生成，Iso-Seq 第一步）",
}

# ccs 的默认过滤阈值（与 pbccs.smk config 默认一致）
DEFAULT_PARAMS = {
    "min_rq": 0.9,
    "min_passes": 3,
    "min_snr": 2.5,
    "min_length": 10,
    "max_length": 50000,
    "top_passes": 60,
}


class PbccsSkill(base.SkillBase):
    software = "pbccs"
    binary = "ccs"  # pbccs conda 包提供的可执行文件是 ccs

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 ccs 命令行。"""
        if subcommand != "ccs":
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        subreads = kw.get("subreads") or kw.get("input")
        if not subreads:
            raise ValueError("缺少必填参数 subreads（输入 subreads BAM）")

        # 输出路径：显式 output > outdir/prefix.bam
        out_bam = kw.get("output")
        outdir = kw.get("outdir")
        prefix = kw.get("prefix")
        if not out_bam:
            sample = Path(subreads).stem.replace(".subreads", "")
            if not prefix:
                prefix = f"{sample}.chunk{kw.get('chunk_num', 1)}"
            if outdir:
                outdir_path = Path(outdir)
            else:
                outdir_path = Path(subreads).parent
            out_bam = str(outdir_path / f"{prefix}.bam")

        cmd += [str(subreads), out_bam]

        # 报告文件：与 out_bam 同前缀
        out_prefix = str(out_bam)
        if out_prefix.endswith(".bam"):
            out_prefix = out_prefix[:-4]
        cmd += ["--report-file", f"{out_prefix}.report.txt"]
        cmd += ["--report-json", f"{out_prefix}.report.json"]
        cmd += ["--metrics-json", f"{out_prefix}.metrics.json.gz"]

        # 分块：--chunk N/TOTAL（若给出 chunk_num/chunk_total 或 chunk 字符串）
        chunk = kw.get("chunk")
        if chunk:
            cmd += ["--chunk", str(chunk)]
        elif kw.get("chunk_num") is not None:
            chunk_total = kw.get("chunk_total", 1)
            cmd += ["--chunk", f"{kw['chunk_num']}/{chunk_total}"]

        # 过滤阈值（仅当用户显式给出时追加；否则走工具默认）
        # 注意：参数名用下划线（min_rq），CLI 旗标用连字符（--min-rq）
        for param, default in DEFAULT_PARAMS.items():
            val = kw.get(param)
            if val is not None:
                cmd += [f"--{param.replace('_', '-')}", str(val)]

        # 线程注入
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-j", str(threads)]

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
        prog="pbccs-skill",
        description="pbccs (ccs) native 技能驱动（自动线程/内存/分块优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("ccs", help=SUBCOMMANDS["ccs"])
    pc.add_argument("--subreads", help="输入 subreads BAM（*.subreads.bam）")
    pc.add_argument("--input", help="输入 subreads BAM 的别名")
    pc.add_argument("-o", "--output", help="输出 CCS BAM 路径（缺省自动生成）")
    pc.add_argument("-d", "--outdir", help="输出目录")
    pc.add_argument("--prefix", help="输出前缀（默认 <sample>.chunk<chunk_num>）")
    pc.add_argument("--chunk", help="分块字符串，如 1/4（与 chunk-num/chunk-total 二选一）")
    pc.add_argument("--chunk-num", type=int, help="当前分块编号（1-based）")
    pc.add_argument("--chunk-total", type=int, help="总分块数")
    pc.add_argument("--min-rq", type=float, help="最小读取质量阈值（默认 0.9）")
    pc.add_argument("--min-passes", type=int, help="最小 subread 通过次数（默认 3）")
    pc.add_argument("--min-snr", type=float, help="最小信噪比（默认 2.5）")
    pc.add_argument("--min-length", type=int, help="最小序列长度（默认 10）")
    pc.add_argument("--max-length", type=int, help="最大序列长度（默认 50000）")
    pc.add_argument("--top-passes", type=int, help="每个 ZMW 最多使用通过次数（默认 60）")
    pc.add_argument("--extra-args", help="透传给 ccs 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pc)

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
        skill = PbccsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PbccsSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    # ccs 无 stdout 输出；stderr 直接透传
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
