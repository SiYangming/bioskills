#!/usr/bin/env python3
"""orthomcl native 标准入口驱动（OrthoMCL v2.0.9；说明型）。

⚠️ DEPRECATED：OrthoMCL 已停止维护（官方推荐 OrthoFinder 替代），且流程依赖
MySQL 数据库。新项目请改用 OrthoFinder（modules/orthofinder/）。

本驱动为「说明型 + 命令构造」：不实际运行 OrthoMCL 脚本（软件 deprecated、依赖 MySQL），
按官方流程构造各步骤命令行，供历史复现 / 文档化调用 / Agent 展示。子命令对应
OrthoMCL 官方脚本：

  adjust_fasta    orthomclAdjustFasta <species> <fasta> <id_length>
  filter_fasta    orthomclFilterFasta <input_dir> [<min_len>] [<max_percent_stop>]
  blast_parser    orthomclBlastParser <blast_output> <compliant_fasta_dir>   # stdout >> similarSequences.txt
  load_blast      orthomclLoadBlast <orthomcl.config> <similarSequences.txt>
  pairs           orthomclPairs <orthomcl.config> <pairs.log> <cleanup>
  dump_pairs      orthomclDumpPairsFiles <orthomcl.config>                   # 产出 mclInput + pairs/
  mcl_to_groups   orthomclMclToGroups <prefix> <start>                       # stdin mclOutput -> stdout groups.txt
  install_schema  orthomclInstallSchema <orthomcl.config> <schema.log> [<install.log>]

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py adjust_fasta ncra proteome.fasta 10
   python main.py filter_fasta compliantFasta 30 20
   python main.py blast_parser blast.out compliantFasta > similarSequences.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：已安装 OrthoMCL 2.0.9（脚本在 PATH，bioconda orthomcl=2.0.9 或官方 tarball，
见 README「环境安装」）。各脚本无 --version 旗标；本驱动不执行真实流程（仅命令构造）。
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
    "adjust_fasta": "orthomclAdjustFasta：规范化蛋白 FASTA（>物种|基因ID）",
    "filter_fasta": "orthomclFilterFasta：过滤低质量序列 → goodProteins.fasta",
    "blast_parser": "orthomclBlastParser：解析 BLAST/DIAMOND 结果 → similarSequences.txt（stdout）",
    "load_blast": "orthomclLoadBlast：把相似序列导入 MySQL",
    "pairs": "orthomclPairs：寻找 ortholog / in-paralog 对",
    "dump_pairs": "orthomclDumpPairsFiles：导出 mclInput 与 pairs/ 目录",
    "mcl_to_groups": "orthomclMclToGroups：MCL 聚类结果编号 → groups.txt（stdin/stdout）",
    "install_schema": "orthomclInstallSchema：安装 OrthoMCL 数据库表",
}

# 子命令 -> 官方可执行脚本名
_BINARIES = {
    "adjust_fasta": "orthomclAdjustFasta",
    "filter_fasta": "orthomclFilterFasta",
    "blast_parser": "orthomclBlastParser",
    "load_blast": "orthomclLoadBlast",
    "pairs": "orthomclPairs",
    "dump_pairs": "orthomclDumpPairsFiles",
    "mcl_to_groups": "orthomclMclToGroups",
    "install_schema": "orthomclInstallSchema",
}

DEPRECATED_NOTE = (
    "⚠️ OrthoMCL 已停止维护（推荐用 OrthoFinder 替代，见 modules/orthofinder/），且流程依赖 "
    "MySQL：本模块仅作历史参考登记，以下命令构造仅供复现历史分析，新项目请用 OrthoFinder。"
)


class OrthomclSkill(base.SkillBase):
    software = "orthomcl"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        注意：OrthoMCL 各脚本无多线程选项，此值仅作接口占位（不注入 argv）；
        重计算（MCL 聚类）走 modules/mcl/ 的 cluster 子命令。
        """
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析 OrthoMCL 脚本（找不到会抛错）。"""
        try:
            bin_name = _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行脚本 '{bin_name}'：请先安装 OrthoMCL 2.0.9 并把其 bin 目录加入 "
                f"PATH（mamba create -n orthomcl-native -c conda-forge -c bioconda orthomcl=2.0.9，"
                f"或取官方 tarball orthomclSoftware-v2.0.9；见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造（不执行）OrthoMCL 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "adjust_fasta":
            return self._build_adjust_fasta(bin_path, **kw)
        if subcommand == "filter_fasta":
            return self._build_filter_fasta(bin_path, **kw)
        if subcommand == "blast_parser":
            return self._build_blast_parser(bin_path, **kw)
        if subcommand == "load_blast":
            return self._build_load_blast(bin_path, **kw)
        if subcommand == "pairs":
            return self._build_pairs(bin_path, **kw)
        if subcommand == "dump_pairs":
            return self._build_dump_pairs(bin_path, **kw)
        if subcommand == "mcl_to_groups":
            return self._build_mcl_to_groups(bin_path, **kw)
        return self._build_install_schema(bin_path, **kw)

    def _require(self, kw: dict, key: str, msg: str):
        val = kw.get(key)
        if val is None or val == "":
            raise RuntimeError(msg)
        return val

    # -- 各子命令 ---------------------------------------------------------- #
    def _build_adjust_fasta(self, bin_path: str, **kw) -> list[str]:
        species = self._require(kw, "species", "adjust_fasta 需要 species（物种缩写，如 ncra）")
        fasta = self._require(kw, "fasta", "adjust_fasta 需要 fasta（输入蛋白 FASTA）")
        idlen = self._require(kw, "id_length", "adjust_fasta 需要 id_length（基因 ID 截取长度，如 10）")
        return [bin_path, str(species), str(fasta), str(idlen)]

    def _build_filter_fasta(self, bin_path: str, **kw) -> list[str]:
        input_dir = self._require(kw, "input_dir", "filter_fasta 需要 input_dir（compliantFasta 目录）")
        min_len = kw.get("min_len")
        max_stop = kw.get("max_percent_stop")
        cmd = [bin_path, str(input_dir)]
        if min_len is not None:
            cmd.append(str(min_len))
            if max_stop is not None:
                cmd.append(str(max_stop))
        return cmd

    def _build_blast_parser(self, bin_path: str, **kw) -> list[str]:
        blast_output = self._require(kw, "blast_output", "blast_parser 需要 blast_output（BLAST/DIAMOND 输出）")
        compliant = self._require(kw, "compliant_dir", "blast_parser 需要 compliant_dir（compliantFasta 目录）")
        return [bin_path, str(blast_output), str(compliant)]

    def _build_load_blast(self, bin_path: str, **kw) -> list[str]:
        config = self._require(kw, "config", "load_blast 需要 config（orthomcl.config）")
        similar = self._require(kw, "similar_sequences", "load_blast 需要 similar_sequences（similarSequences.txt）")
        return [bin_path, str(config), str(similar)]

    def _build_pairs(self, bin_path: str, **kw) -> list[str]:
        config = self._require(kw, "config", "pairs 需要 config（orthomcl.config）")
        log = self._require(kw, "log", "pairs 需要 log（pairs.log 路径）")
        cleanup = kw.get("cleanup") or "yes"
        return [bin_path, str(config), str(log), str(cleanup)]

    def _build_dump_pairs(self, bin_path: str, **kw) -> list[str]:
        config = self._require(kw, "config", "dump_pairs 需要 config（orthomcl.config）")
        return [bin_path, str(config)]

    def _build_mcl_to_groups(self, bin_path: str, **kw) -> list[str]:
        prefix = self._require(kw, "prefix", "mcl_to_groups 需要 prefix（OCG 前缀，如 OCG）")
        start = self._require(kw, "start", "mcl_to_groups 需要 start（起始编号，如 1）")
        return [bin_path, str(prefix), str(start)]

    def _build_install_schema(self, bin_path: str, **kw) -> list[str]:
        config = self._require(kw, "config", "install_schema 需要 config（orthomcl.config）")
        log = self._require(kw, "log", "install_schema 需要 log（schema 日志路径）")
        cmd = [bin_path, str(config), str(log)]
        if kw.get("db_log"):
            cmd.append(str(kw["db_log"]))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程占位/临时目录）。"""
    p.add_argument("--threads", type=int, help="线程数占位（OrthoMCL 无多线程选项，不注入 argv）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="orthomcl-skill",
        description="OrthoMCL native 技能驱动（说明型：构造 OrthoMCL 命令，已停止维护，仅历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("adjust_fasta", help=SUBCOMMANDS["adjust_fasta"])
    pa.add_argument("species", help="物种缩写（属名前2字母+种名前3字母，如 ncra）")
    pa.add_argument("fasta", help="输入蛋白 FASTA")
    pa.add_argument("id_length", type=int, help="基因 ID 截取长度（如 10）")
    _add_runtime_opts(pa)

    pf = sub.add_parser("filter_fasta", help=SUBCOMMANDS["filter_fasta"])
    pf.add_argument("input_dir", help="compliantFasta 目录")
    pf.add_argument("--min-len", type=int, default=10, help="允许的最短蛋白长度（默认 10）")
    pf.add_argument("--max-percent-stop", type=int, default=20, help="终止密码子最大比例 %%（默认 20）")
    _add_runtime_opts(pf)

    pb = sub.add_parser("blast_parser", help=SUBCOMMANDS["blast_parser"])
    pb.add_argument("blast_output", help="BLAST/DIAMOND 输出（outfmt 6）")
    pb.add_argument("compliant_dir", help="compliantFasta 目录")
    _add_runtime_opts(pb)

    pl = sub.add_parser("load_blast", help=SUBCOMMANDS["load_blast"])
    pl.add_argument("config", help="orthomcl.config")
    pl.add_argument("similar_sequences", help="similarSequences.txt")
    _add_runtime_opts(pl)

    pp = sub.add_parser("pairs", help=SUBCOMMANDS["pairs"])
    pp.add_argument("config", help="orthomcl.config")
    pp.add_argument("log", help="pairs.log 路径")
    pp.add_argument("--cleanup", default="yes", help="结束后是否清理中间数据（yes|no，默认 yes）")
    _add_runtime_opts(pp)

    pd = sub.add_parser("dump_pairs", help=SUBCOMMANDS["dump_pairs"])
    pd.add_argument("config", help="orthomcl.config")
    _add_runtime_opts(pd)

    pm = sub.add_parser("mcl_to_groups", help=SUBCOMMANDS["mcl_to_groups"])
    pm.add_argument("prefix", help="OCG 前缀（如 OCG）")
    pm.add_argument("start", type=int, help="起始编号（如 1）")
    _add_runtime_opts(pm)

    pi = sub.add_parser("install_schema", help=SUBCOMMANDS["install_schema"])
    pi.add_argument("config", help="orthomcl.config")
    pi.add_argument("log", help="schema 日志路径")
    pi.add_argument("--db-log", help="可选：数据库安装日志")
    _add_runtime_opts(pi)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = OrthomclSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OrthomclSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    # deprecated 提示（stderr，不干扰 stdout 产物）
    print(DEPRECATED_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；deprecated 软件仅供历史复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    if ns.subcommand in ("blast_parser", "mcl_to_groups"):
        print("[hint] 该步骤结果写 stdout，请重定向到文件"
              "（blast_parser >> similarSequences.txt；mcl_to_groups > groups.txt）", file=sys.stderr)
    if ns.subcommand == "dump_pairs":
        print("[hint] 产物为 mclInput（ABC）与 pairs/ 目录；随后用 modules/mcl/ 的 cluster 子命令聚类",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
