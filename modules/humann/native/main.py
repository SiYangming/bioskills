#!/usr/bin/env python3
"""humann native 标准入口驱动。

HUMAnN 是宏基因组 / 宏转录组功能分析流程（prescreen → nucleotide search → translated
search → 定量）。本驱动覆盖高频用法：

1. CLI 直跑（人类 / Shell）：
   python main.py run --input reads.fastq --output outdir --threads 8 --bypass-prescreen
   python main.py renorm --input outdir/*_genefamilies.tsv --output outdir/genefamilies_cpm.tsv --units cpm
   python main.py join --input outdir/ --output all_genefamilies.tsv --file-name genefamilies.tsv
   python main.py regroup --input all_genefamilies.tsv --output all_genefamilies_ec.tsv --groups ec
   python main.py databases --available
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

子命令到实际可执行文件的映射（bioconda humann / PyPI 安装后均提供 console scripts）：
  run       -> humann                    （主流程；3.x 与 4.0.0a1 参数一致）
  renorm    -> humann_renorm_table       （归一化：cpm / relab）
  join      -> humann_join_tables        （合并多样本表格）
  regroup   -> humann_regroup_table      （重分组：uniref90/uniref50/ec/... 或自定义映射）
  databases -> humann_databases          （查询 / 下载 ChocoPhlAn、UniRef、utility 数据库）

每个子命令支持 --threads / --tmpdir 运行期覆盖（线程仅 run 注入 humann --threads；
其余为表格/数据库脚本，单线程，契约字段保留）。
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
    "run": "直驱 humann 主流程：reads/比对 -> 基因家族与通路丰度（--input --output --threads，支持 --bypass-prescreen 等）",
    "renorm": "归一化丰度表（humann_renorm_table：cpm / relab）",
    "join": "合并多样本表格（humann_join_tables，按 --file-name 匹配）",
    "regroup": "按功能分组重映射（humann_regroup_table：uniref90/uniref50/ec/metacyc-rxn/... 或 --custom）",
    "databases": "数据库查询 / 下载（humann_databases：--available 或 --download <database> <build> <location>）",
}

# 辅助 console script 名（bioconda humann=3.9 / PyPI 均一致）
TOOL_SCRIPTS = {
    "renorm": "humann_renorm_table",
    "join": "humann_join_tables",
    "regroup": "humann_regroup_table",
    "databases": "humann_databases",
}


class HumannSkill(base.SkillBase):
    software = "humann"
    binary = "humann"

    def _resolve_tool_binary(self, subcommand: str) -> str:
        """解析辅助脚本路径：优先 PATH，找不到时给出安装提示。"""
        import shutil

        script = TOOL_SCRIPTS[subcommand]
        path = shutil.which(script)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{script}'（humann 安装应提供该 console script），"
                f"请先通过 Conda/Docker/Apptainer 安装 humann。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 humann 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        if subcommand == "run":
            cmd: list[str] = [self._resolve_binary()]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            return self._build_run(cmd, threads, kw)

        # 辅助脚本（单线程；--threads 为契约字段不注入）
        script = self._resolve_tool_binary(subcommand)
        return self._build_tool(subcommand, script, kw)

    # ------------------------------------------------------------------ #
    # run：直驱 humann 主流程
    # ------------------------------------------------------------------ #
    def _build_run(self, cmd: list[str], threads: int, kw: dict) -> list[str]:
        input_f = kw.get("input")
        output = kw.get("output")
        if not input_f:
            raise ValueError("run 缺少必填参数 input（reads/比对 文件）")
        if not output:
            raise ValueError("run 缺少必填参数 output（输出目录）")
        cmd += ["--input", str(input_f), "--output", str(output)]
        cmd += ["--threads", str(threads)]

        if kw.get("input_format"):
            cmd += ["--input-format", str(kw["input_format"])]
        if kw.get("memory_use"):
            cmd += ["--memory-use", str(kw["memory_use"])]
        for flag in (
            "bypass_prescreen",
            "bypass_nucleotide_search",
            "bypass_nucleotide_index",
            "bypass_translated_search",
        ):
            if kw.get(flag):
                cmd.append("--" + flag.replace("_", "-"))
        if kw.get("resume"):
            cmd.append("--resume")
        if kw.get("remove_temp_output"):
            cmd.append("--remove-temp-output")
        if kw.get("output_basename"):
            cmd += ["--output-basename", str(kw["output_basename"])]
        if kw.get("verbose"):
            cmd.append("--verbose")
        return self._append_extra(cmd, kw)

    # ------------------------------------------------------------------ #
    # 辅助脚本：renorm / join / regroup / databases
    # ------------------------------------------------------------------ #
    def _build_tool(self, subcommand: str, script: str, kw: dict) -> list[str]:
        cmd: list[str] = [script]

        if subcommand == "renorm":
            input_f = kw.get("input")
            output = kw.get("output")
            if not input_f:
                raise ValueError("renorm 缺少必填参数 input（丰度表）")
            if not output:
                raise ValueError("renorm 缺少必填参数 output（输出文件）")
            cmd += ["--input", str(input_f), "--output", str(output)]
            units = kw.get("units")
            if units:
                cmd += ["--units", str(units)]

        elif subcommand == "join":
            input_f = kw.get("input")
            output = kw.get("output")
            if not input_f:
                raise ValueError("join 缺少必填参数 input（表格目录）")
            if not output:
                raise ValueError("join 缺少必填参数 output（合并输出文件）")
            cmd += ["--input", str(input_f), "--output", str(output)]
            if kw.get("file_name"):
                cmd += ["--file_name", str(kw["file_name"])]
            if kw.get("search_subdirectories"):
                cmd.append("--search-subdirectories")

        elif subcommand == "regroup":
            input_f = kw.get("input")
            output = kw.get("output")
            if not input_f:
                raise ValueError("regroup 缺少必填参数 input（丰度表）")
            if not output:
                raise ValueError("regroup 缺少必填参数 output（输出文件）")
            cmd += ["--input", str(input_f), "--output", str(output)]
            if kw.get("groups"):
                cmd += ["--groups", str(kw["groups"])]
            elif kw.get("custom"):
                cmd += ["--custom", str(kw["custom"])]
            else:
                raise ValueError("regroup 需提供 groups（如 uniref90/ec）或 custom（自定义映射文件）")

        elif subcommand == "databases":
            if kw.get("available"):
                cmd.append("--available")
            else:
                database = kw.get("database")
                build = kw.get("build")
                location = kw.get("location")
                if not (database and build and location):
                    raise ValueError("databases 需提供 --database <名> --build <full/demo/...> --location <安装目录>，或 --available 查询")
                cmd += ["--download", str(database), str(build), str(location)]
            if kw.get("update_config") is not None:
                cmd += ["--update-config", "yes" if kw["update_config"] else "no"]

        else:  # pragma: no cover
            raise ValueError(f"未知子命令: {subcommand}")

        return self._append_extra(cmd, kw)

    @staticmethod
    def _append_extra(cmd: list[str], kw: dict) -> list[str]:
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="humann-skill",
        description="humann native 技能驱动（宏基因组功能分析；自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run（直驱 humann 主流程）
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("--input", "-i", required=True, help="输入文件：reads（fastq/fastq.gz/fasta/fasta.gz）或比对（sam/bam）")
    pr.add_argument("--output", "-o", required=True, help="输出目录（HUMAnN 结果目录）")
    pr.add_argument("--input-format", help="输入格式（默认按扩展名推断）")
    pr.add_argument("--memory-use", choices=["minimum", "normal", "more", "maximum"],
                    help="内存策略")
    pr.add_argument("--bypass-prescreen", action="store_true", dest="bypass_prescreen",
                    help="跳过 tier1 prescreen（MetaPhlAn 物种预筛）")
    pr.add_argument("--bypass-nucleotide-search", action="store_true", dest="bypass_nucleotide_search",
                    help="跳过 tier2 nucleotide search（ChocoPhlAn）")
    pr.add_argument("--bypass-nucleotide-index", action="store_true", dest="bypass_nucleotide_index",
                    help="跳过 nucleotide index（需要数据库含 .1.bt2 等索引）")
    pr.add_argument("--bypass-translated-search", action="store_true", dest="bypass_translated_search",
                    help="跳过 tier3 translated search（UniRef）")
    pr.add_argument("--resume", "-r", action="store_true", help="断点续跑（保留已存在输出）")
    pr.add_argument("--remove-temp-output", action="store_true", dest="remove_temp_output",
                    help="运行结束后清理中间临时文件")
    pr.add_argument("--output-basename", dest="output_basename", help="输出文件前缀（默认取输入名）")
    pr.add_argument("--verbose", "-v", action="store_true", help="详细日志")
    pr.add_argument("--extra-args", help="透传给 humann 的额外参数")
    _add_runtime_opts(pr)

    # renorm（humann_renorm_table）
    pn = sub.add_parser("renorm", help=SUBCOMMANDS["renorm"])
    pn.add_argument("--input", "-i", required=True, help="输入丰度表（tsv / biom）")
    pn.add_argument("--output", "-o", required=True, help="输出文件（默认 cpm 归一化）")
    pn.add_argument("--units", choices=["cpm", "relab"], default="cpm",
                    help="归一化方案：cpm（每百万拷贝）/ relab（相对丰度）；默认 cpm")
    pn.add_argument("--extra-args", help="透传给 humann_renorm_table 的额外参数（如 --mode levelwise）")
    _add_runtime_opts(pn)

    # join（humann_join_tables）
    pj = sub.add_parser("join", help=SUBCOMMANDS["join"])
    pj.add_argument("--input", "-i", required=True, help="输入表格目录")
    pj.add_argument("--output", "-o", required=True, help="合并输出文件")
    pj.add_argument("--file-name", dest="file_name", help="仅合并文件名包含该字符串的表（如 genefamilies.tsv）")
    pj.add_argument("--search-subdirectories", dest="search_subdirectories", action="store_true",
                    help="递归搜索输入目录的子目录")
    pj.add_argument("--extra-args", help="透传给 humann_join_tables 的额外参数")
    _add_runtime_opts(pj)

    # regroup（humann_regroup_table）
    pg = sub.add_parser("regroup", help=SUBCOMMANDS["regroup"])
    pg.add_argument("--input", "-i", required=True, help="输入丰度表")
    pg.add_argument("--output", "-o", required=True, help="输出文件")
    gg = pg.add_mutually_exclusive_group(required=True)
    gg.add_argument("--groups", "-g", help="内置分组：uniref90/uniref50/uniref100/ec/metacyc-rxn/ko/...（--available 不适用）")
    gg.add_argument("--custom", "-c", help="自定义映射文件（tsv / tsv.gz）")
    pg.add_argument("--extra-args", help="透传给 humann_regroup_table 的额外参数（如 --function sum）")
    _add_runtime_opts(pg)

    # databases（humann_databases）
    pd = sub.add_parser("databases", help=SUBCOMMANDS["databases"])
    pd.add_argument("--available", action="store_true", help="列出可选数据库（chocophlan/uniref/utility 等）")
    pd.add_argument("--database", help="数据库名（chocophlan/uniref/utility）")
    pd.add_argument("--build", help="构建类型（full/demo/...；--available 查询为准）")
    pd.add_argument("--location", help="安装目录（下载后写库；建议用户目录）")
    pd.add_argument("--update-config", action="store_true", default=None, help="更新默认配置指向新库（默认 no）")
    pd.add_argument("--no-update-config", dest="update_config", action="store_false",
                    help="不更新配置（默认）")
    pd.add_argument("--extra-args", help="透传给 humann_databases 的额外参数（如 --database-location <URL>）")
    _add_runtime_opts(pd)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅 run 注入 --threads；其余为契约字段）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = HumannSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = HumannSkill()
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
