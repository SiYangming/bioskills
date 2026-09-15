#!/usr/bin/env python3
"""biom-format native 标准入口驱动（BIOM 特征表工具集，CLI 命令 biom）。

BIOM（Biological Observation Matrix）是微生物组特征表的标准化格式，biom-format 提供
其读写与统计工具集；本驱动封装 convert（BIOM/TSV/JSON 互转）与 summarize-table（统计摘要）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py convert -i feature-table.biom -o feature-table.tsv --to-tsv
   python main.py convert -i otu_table.txt -o table.biom --table-type "OTU table" --to-hdf5
   python main.py summarize-table -i feature-table.biom -o summary.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

说明：biom convert / summarize-table 均为单线程，`--threads` 会被接受但不注入（保持接口统一）。
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

SUBCOMMANDS = {
    "convert": "特征表格式互转：BIOM/TSV/JSON（biom convert，--to-tsv/--to-json/--to-hdf5）",
    "summarize-table": "特征表统计摘要：样本数/观测数/总计数/密度（biom summarize-table）",
}


class BiomFormatSkill(base.SkillBase):
    software = "biom-format"
    binary = "biom"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()

        if subcommand == "convert":
            return self._cmd_convert(binary, kw)
        if subcommand == "summarize-table":
            return self._cmd_summarize(binary, kw)
        raise ValueError(f"未知子命令: {subcommand}")

    def _cmd_convert(self, binary: str, kw: dict) -> list[str]:
        inp = kw.get("input")
        out = kw.get("output")
        if not inp:
            raise ValueError("convert 缺少输入 -i/--input")
        if not out:
            raise ValueError("convert 缺少输出 -o/--output")
        fmt_flags = [f for f, k in (("--to-tsv", "to_tsv"), ("--to-json", "to_json"),
                                    ("--to-hdf5", "to_hdf5")) if kw.get(k)]
        if len(fmt_flags) != 1:
            raise ValueError("convert 需要且仅需一个输出格式项：--to-tsv / --to-json / --to-hdf5")

        cmd = [binary, "convert", "-i", str(inp), "-o", str(out), fmt_flags[0]]
        if kw.get("table_type"):
            cmd += ["--table-type", str(kw["table_type"])]
        if kw.get("header_key"):
            cmd += ["--header-key", str(kw["header_key"])]
        if kw.get("sample_metadata_fp"):
            cmd += ["-m", str(kw["sample_metadata_fp"])]
        if kw.get("observation_metadata_fp"):
            cmd += ["--observation-metadata-fp", str(kw["observation_metadata_fp"])]
        if kw.get("collapsed_samples"):
            cmd.append("--collapsed-samples")
        if kw.get("collapsed_observations"):
            cmd.append("--collapsed-observations")
        if kw.get("output_metadata_id"):
            cmd += ["--output-metadata-id", str(kw["output_metadata_id"])]
        if kw.get("process_obs_metadata"):
            cmd += ["--process-obs-metadata", str(kw["process_obs_metadata"])]
        if kw.get("tsv_metadata_formatter"):
            cmd += ["--tsv-metadata-formatter", str(kw["tsv_metadata_formatter"])]
        return cmd

    def _cmd_summarize(self, binary: str, kw: dict) -> list[str]:
        inp = kw.get("input")
        if not inp:
            raise ValueError("summarize-table 缺少输入 -i/--input")
        cmd = [binary, "summarize-table", "-i", str(inp)]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        if kw.get("qualitative"):
            cmd.append("--qualitative")
        if kw.get("observations"):
            cmd.append("--observations")
        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int,
                   help="覆盖默认线程数（biom 单线程，接受但忽略）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="biom-format-skill",
        description="biom-format native 技能驱动（BIOM 特征表 convert / summarize-table）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # convert
    pc = sub.add_parser("convert", help=SUBCOMMANDS["convert"])
    pc.add_argument("-i", "--input", required=True, help="输入特征表文件（BIOM/JSON/经典 TSV）")
    pc.add_argument("-o", "--output", required=True, help="输出特征表文件")
    fmt = pc.add_mutually_exclusive_group()
    fmt.add_argument("--to-tsv", action="store_true", help="输出 TSV")
    fmt.add_argument("--to-json", action="store_true", help="输出 JSON")
    fmt.add_argument("--to-hdf5", action="store_true", help="输出 HDF5（BIOM 二进制）")
    pc.add_argument("--table-type", help='表类型（如 "OTU table"）')
    pc.add_argument("--header-key", help="观测元数据键（如 taxonomy）")
    pc.add_argument("-m", "--sample-metadata-fp", help="样本元数据文件")
    pc.add_argument("--observation-metadata-fp", help="观测元数据文件")
    pc.add_argument("--collapsed-samples", action="store_true", help="折叠样本元数据为单列")
    pc.add_argument("--collapsed-observations", action="store_true", help="折叠观测元数据为单列")
    pc.add_argument("--output-metadata-id", help="输出元数据 id")
    pc.add_argument("--process-obs-metadata", help="观测元数据处理方式（如 taxonomy）")
    pc.add_argument("--tsv-metadata-formatter", help="TSV 元数据格式化器")
    _add_runtime_opts(pc)

    # summarize-table
    ps = sub.add_parser("summarize-table", help=SUBCOMMANDS["summarize-table"])
    ps.add_argument("-i", "--input", required=True, help="输入 BIOM 特征表")
    ps.add_argument("-o", "--output", help="输出统计摘要文件（缺省写 stdout）")
    ps.add_argument("--qualitative", action="store_true", help="以定性（存在/缺失）统计")
    ps.add_argument("--observations", action="store_true", help="增加逐观测统计")
    _add_runtime_opts(ps)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = BiomFormatSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BiomFormatSkill()
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

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
