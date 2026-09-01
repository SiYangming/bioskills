#!/usr/bin/env python3
"""fastp native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell / 编排器）：
   python main.py run -i R1.fq.gz -I R2.fq.gz -o clean_R1.fq.gz -O clean_R2.fq.gz \
       -h report.html -j report.json --threads 8 --detect-adapter-for-pe
   单端：
   python main.py run -i R1.fq.gz -o clean_R1.fq.gz -h report.html -j report.json
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑对齐 subworkflow/fastp_bwa_samtools/fastp_bwa_samtools.py 的
fastp stage 调用约定（run 子命令 + -i/-I/-o/-O/-h/-j）。

fastp 版本注意：
  fastp 0.20.0 起线程参数由 -t 改为 -w/--thread（-t 现为 --trim_tail1）。
  本驱动一律输出 -w，请勿用 -t 传线程。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "run": "单/双端 FASTQ 质控 + 接头检测/切除 + HTML/JSON 报告（fastp -i/-o/-h/-j）",
}

# fastp 0.20+ 线程参数（-t 已被 --trim_tail1 占用）
THREAD_FLAG = "-w"


class FastpSkill(base.SkillBase):
    software = "fastp"
    binary = "fastp"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 全局默认（fastp 无特殊子命令差异）。"""
        if override and override > 0:
            return override
        return self.cpus

    @staticmethod
    def _mkdir_parents(*paths: str | None) -> None:
        """为输出文件自动创建父目录。"""
        for p in paths:
            if p:
                Path(p).parent.mkdir(parents=True, exist_ok=True)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 fastp 命令行。"""
        if subcommand != "run":
            raise ValueError(f"未知子命令: {subcommand}（fastp 仅支持 run）")

        in1 = kw.get("in1")
        out1 = kw.get("out1")
        if not in1:
            raise ValueError("缺少必填参数 in1（输入 R1 FASTQ）")
        if not out1:
            raise ValueError("缺少必填参数 out1（输出 R1 FASTQ）")

        bin_path = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = [bin_path, "-i", str(in1), "-o", str(out1)]

        if kw.get("in2"):
            cmd += ["-I", str(kw["in2"])]
        if kw.get("out2"):
            cmd += ["-O", str(kw["out2"])]
        if kw.get("html"):
            cmd += ["-h", str(kw["html"])]
        if kw.get("json"):
            cmd += ["-j", str(kw["json"])]

        # 线程（fastp 0.20+ 为 -w/--thread）
        cmd += [THREAD_FLAG, str(threads)]

        if kw.get("adapter_sequence"):
            cmd += ["--adapter_sequence", str(kw["adapter_sequence"])]
        if kw.get("detect_adapter_for_pe"):
            cmd.append("--detect_adapter_for_pe")
        if kw.get("qualified_quality_phred") is not None:
            cmd += ["-q", str(kw["qualified_quality_phred"])]
        if kw.get("unqualified_percent_limit") is not None:
            cmd += ["-u", str(kw["unqualified_percent_limit"])]
        if kw.get("length_required") is not None:
            cmd += ["-l", str(kw["length_required"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 输出父目录自动创建（报告/产物路径可跨目录）
        self._mkdir_parents(out1, kw.get("out2"), kw.get("html"), kw.get("json"))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fastp-skill",
        description="fastp native 技能驱动（QC + 去接头 + 报告；自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run（注意：子 parser 关闭默认 -h，把 -h 留给 --html；--help 仍可用）
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"], add_help=False)
    pr.add_argument("--help", action="help", help="显示 run 子命令帮助")
    pr.add_argument("-i", "--in1", required=True, help="输入 R1 FASTQ(.gz)")
    pr.add_argument("-o", "--out1", required=True, help="输出 R1 清洁 FASTQ(.gz)")
    pr.add_argument("-I", "--in2", help="输入 R2 FASTQ(.gz)（双端模式）")
    pr.add_argument("-O", "--out2", help="输出 R2 清洁 FASTQ(.gz)（双端模式）")
    pr.add_argument("-h", "--html", help="HTML 质控报告路径")
    pr.add_argument("-j", "--json", help="JSON 质控报告路径")
    pr.add_argument("--adapter-sequence", dest="adapter_sequence",
                    help="R1 3' 端接头序列（IUPAC；不指定则自动检测）")
    pr.add_argument("--detect-adapter-for-pe", dest="detect_adapter_for_pe",
                    action="store_true", help="双端模式通过 R1/R2 重叠检测接头")
    pr.add_argument("--qualified-quality-phred", dest="qualified_quality_phred",
                    type=int, help="合格碱基 phred 阈值（默认 15）")
    pr.add_argument("--unqualified-percent-limit", dest="unqualified_percent_limit",
                    type=int, help="不合格碱基比例上限 %%（默认 40）")
    pr.add_argument("--length-required", dest="length_required",
                    type=int, help="最短 read 长度（默认 15）")
    pr.add_argument("--extra-args", dest="extra_args",
                    help="透传给 fastp 的额外参数（如 --cut_front --cut_tail --cut_right 1）")
    _add_runtime_opts(pr)

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
        skill = FastpSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FastpSkill()
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

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
