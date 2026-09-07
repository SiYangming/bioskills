#!/usr/bin/env python3
"""ncbi-datasets-cli native 标准入口驱动。

模块提供两个并列子命令（datasets 与 dataformat，官方同包发布的两个二进制）：

1. datasets —— NCBI Datasets 下载 / 摘要工具：
     python main.py datasets download GCF_000001405.39 --include genome,gff3 -o ncbi_dataset.zip
     python main.py datasets download --taxon "Homo sapiens" --include genome --dehydrated
     python main.py datasets summary GCF_000001405.39 --json-lines
     python main.py datasets summary --taxon "Homo sapiens"
2. dataformat —— datasets 的格式化兄弟工具（同目录安装）：
     python main.py dataformat tsv genome --package ncbi_dataset.zip     # JSON -> TSV 表
     python main.py dataformat tsv gene  --taxon "Homo sapiens"
3. 自省：python main.py --schema / --list-commands

底层命令映射：
  datasets download  datasets download genome accession <acc...> --include genome,gff3 [-o zip] [--dehydrated]
                    datasets download genome taxon <taxon>
  datasets summary  datasets summary genome accession <acc...> [--as-json-lines] [--report <report>]
                    datasets summary genome taxon <taxon>
  dataformat        dataformat tsv genome --package <zip> [--accession <acc> | --taxon <t> | --dehydrated]
                    dataformat <fmt> <report_type> ...
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 顶层子命令语义（datasets 与 dataformat 为模块的两个并列工具）
SUBCOMMANDS = {
    "datasets": "NCBI Datasets 下载/摘要：datasets download / summary（accession|taxon -> zip / JSON 摘要）",
    "dataformat": "datasets 格式化兄弟工具：dataformat tsv genome --package <zip> -> TSV 表（gene/protein 等同理）",
    "help": "打印模块子命令清单 +（若已安装）真实 datasets --help / dataformat version",
}

# datasets 二级 action（本模块聚焦 genome 数据类型）
DATASET_TYPE = "genome"
DATASET_ACTIONS = ("download", "summary")

# dataformat 常用 report 类型（默认 genome；可扩展 gene/protein/virus 等）
DATAFORMAT_DEFAULT_FMT = "tsv"
DATAFORMAT_DEFAULT_TYPE = "genome"


class NcbiDatasetsCliSkill(base.SkillBase):
    software = "ncbi-datasets-cli"
    binary = "datasets"  # 默认二进制；dataformat 子命令走同包安装的兄弟二进制

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（datasets 自行并发，仅驱动层占位）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_dataformat_binary(self) -> str:
        """解析 dataformat 兄弟二进制（与 datasets 同包安装于同一 bin 目录）。"""
        path = shutil.which("dataformat")
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'dataformat'（与 datasets 同包安装，bash native/install.sh "
                "会把两者放入同一 bin/；或使用官方容器 quay.io/biocontainers/ncbi-datasets-cli）。"
            )
        return path

    def _split_accessions(self, raw: str) -> list[str]:
        """accession 支持逗号 / 空白分隔的多个取值。"""
        return [x for x in raw.replace(",", " ").split() if x]

    # -- 子命令命令行构造 ------------------------------------------------ #
    def _build_datasets(self, action: str, **kw) -> list[str]:
        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        if action == "download":
            # datasets download genome accession <acc...> --include genome,gff3 [-o zip] [--dehydrated]
            accession = kw.get("accession") or kw.get("input")
            taxon = kw.get("taxon")
            if not accession and not taxon:
                raise ValueError("datasets download 需要 accession 或 taxon 之一")
            cmd += ["download", DATASET_TYPE]
            if accession:
                cmd += ["accession"] + self._split_accessions(str(accession))
            else:
                cmd += ["taxon", str(taxon)]
            include = kw.get("include")
            if include is not None:
                cmd += ["--include", str(include)]
            if kw.get("dehydrated"):
                cmd.append("--dehydrated")
            out = kw.get("output_file") or kw.get("output")
            if out:
                cmd += ["--filename", str(out)]

        elif action == "summary":
            # datasets summary genome accession <acc...> [--as-json-lines] [--report <report>]
            accession = kw.get("accession") or kw.get("input")
            taxon = kw.get("taxon")
            if not accession and not taxon:
                raise ValueError("datasets summary 需要 accession 或 taxon 之一")
            cmd += ["summary", DATASET_TYPE]
            if accession:
                cmd += ["accession"] + self._split_accessions(str(accession))
            else:
                cmd += ["taxon", str(taxon)]
            if kw.get("json_lines"):
                cmd.append("--as-json-lines")
            report = kw.get("report")
            if report:
                cmd += ["--report", str(report)]

        else:
            raise ValueError(f"datasets 未知 action: {action}（支持 {DATASET_ACTIONS}）")
        return cmd

    def _build_dataformat(self, **kw) -> list[str]:
        """dataformat tsv genome --package <zip> [--accession/--taxon/--dehydrated] [--fields ...]"""
        binary = self._resolve_dataformat_binary()
        cmd: list[str] = [binary]
        cmd.append(str(kw.get("fmt") or DATAFORMAT_DEFAULT_FMT))
        cmd.append(str(kw.get("report_type") or DATAFORMAT_DEFAULT_TYPE))

        package = kw.get("package")
        accession = kw.get("accession") or kw.get("input")
        taxon = kw.get("taxon")
        if package:
            cmd += ["--package", str(package)]
        elif accession:
            cmd += ["--accession"] + self._split_accessions(str(accession))
        elif taxon:
            cmd += ["--taxon", str(taxon)]
        elif not kw.get("dehydrated") and not kw.get("_allow_no_selector"):
            raise ValueError("dataformat 需要 --package / --accession / --taxon 之一（或 --dehydrated）")
        if kw.get("dehydrated"):
            cmd.append("--dehydrated")
        fields = kw.get("fields")
        if fields:
            cmd += ["--fields", str(fields)]
        return cmd

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据顶层子命令（datasets | dataformat）与参数构建官方 CLI 命令行。"""
        if subcommand == "datasets":
            action = kw.pop("action", None)
            if action not in DATASET_ACTIONS:
                raise ValueError(f"datasets 需要指定 action：{DATASET_ACTIONS}")
            cmd = self._build_datasets(action, **kw)
        elif subcommand == "dataformat":
            cmd = self._build_dataformat(**kw)
        else:
            raise ValueError(f"未知子命令: {subcommand}（支持 datasets / dataformat / help）")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 透传）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（datasets 自行并发，占位）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ncbi-datasets-cli-skill",
        description="ncbi-datasets-cli native 技能驱动（NCBI Datasets 下载/摘要 + dataformat 格式化；两个并列子命令）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<datasets|dataformat>")

    # ---- datasets（二级 download / summary）----
    pd = sub.add_parser("datasets", help=SUBCOMMANDS["datasets"])
    dsub = pd.add_subparsers(dest="action", metavar="<download|summary>", required=True)

    p_dl = dsub.add_parser("download", help="accession/taxon -> 基因组数据包 zip")
    p_dl.add_argument("input", nargs="?", help="NCBI accession（别名 --accession；可多个/逗号分隔）")
    p_dl.add_argument("--accession", help="NCBI accession 的别名")
    p_dl.add_argument("--taxon", help="物种名或 NCBI Taxonomy ID（如 'Homo sapiens' / 9606；与 accession 二选一）")
    p_dl.add_argument("--include", default="genome,gff3", help="数据类型（默认 genome,gff3；如 genome / gff3,gbff）")
    p_dl.add_argument("--dehydrated", action="store_true", help="只下载脱水清单包（含 fetch.txt，需 datasets rehydrate）")
    p_dl.add_argument("-o", "--output-file", dest="output_file", help="输出 zip 文件名（默认 ncbi_dataset.zip）")
    p_dl.add_argument("--extra-args", help="透传给 datasets 的额外参数")
    _add_runtime_opts(p_dl)

    p_sm = dsub.add_parser("summary", help="accession/taxon -> 元数据 JSON 摘要（供 dataformat 转 TSV）")
    p_sm.add_argument("input", nargs="?", help="NCBI accession（别名 --accession）")
    p_sm.add_argument("--accession", help="NCBI accession 的别名")
    p_sm.add_argument("--taxon", help="物种名或 NCBI Taxonomy ID（与 accession 二选一）")
    p_sm.add_argument("--json-lines", dest="json_lines", action="store_true", help="输出 JSON Lines（默认单条 JSON）")
    p_sm.add_argument("--report", help="附加数据报告（如 assembly_stats）")
    p_sm.add_argument("--extra-args", help="透传给 datasets 的额外参数")
    _add_runtime_opts(p_sm)

    # ---- dataformat（兄弟工具；fmt / report_type 位置参数）----
    pf = sub.add_parser("dataformat", help=SUBCOMMANDS["dataformat"])
    pf.add_argument("fmt", nargs="?", default=DATAFORMAT_DEFAULT_FMT,
                    help="输出格式（默认 tsv；其余透传 dataformat 支持值）")
    pf.add_argument("report_type", nargs="?", default=DATAFORMAT_DEFAULT_TYPE,
                    help="数据类型（默认 genome；gene / protein / virus 等透传）")
    pf.add_argument("--package", help="datasets download 产物 zip（推荐 selector）")
    pf.add_argument("--accession", help="NCBI accession（可多个/逗号分隔）")
    pf.add_argument("--taxon", help="物种名或 NCBI Taxonomy ID（与 accession/package 互斥）")
    pf.add_argument("--dehydrated", action="store_true", help="对脱水包目录操作")
    pf.add_argument("--fields", help="TSV 字段列表（逗号分隔；dataformat 支持项）")
    pf.add_argument("--extra-args", help="透传给 dataformat 的额外参数")
    _add_runtime_opts(pf)

    # help（自包含）
    sub.add_parser("help", help=SUBCOMMANDS["help"])

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = NcbiDatasetsCliSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not getattr(ns, "subcommand", None):
        build_parser().print_help(sys.stderr)
        return 2

    if ns.subcommand == "help":
        print("ncbi-datasets-cli native 驱动子命令：")
        for k, v in SUBCOMMANDS.items():
            print(f"  {k:10s} {v}")
        print("示例：python main.py datasets download GCF_000001405.39 --include genome,gff3 -o ncbi_dataset.zip")
        print("      python main.py datasets summary --taxon \"Homo sapiens\"")
        print("      python main.py dataformat tsv genome --package ncbi_dataset.zip > summary.tsv")
        if shutil.which("datasets"):
            print("\n真实 datasets --help：")
            res = base.run_command(["datasets", "--help"], check=False)
            sys.stdout.write(res.stdout or "")
            sys.stderr.write(res.stderr or "")
        if shutil.which("dataformat"):
            print("\n真实 dataformat version：")
            res = base.run_command(["dataformat", "version"], check=False)
            sys.stdout.write(res.stdout or "")
            sys.stderr.write(res.stderr or "")
        if not shutil.which("datasets") and not shutil.which("dataformat"):
            print("\n未检测到 datasets/dataformat 二进制；安装后（bash native/install.sh）可查看官方 --help")
        return 0

    skill = NcbiDatasetsCliSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "action", "threads", "tmpdir") and v is not None}
    kw["threads"] = getattr(ns, "threads", None)
    if ns.subcommand == "datasets":
        kw["action"] = ns.action

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
