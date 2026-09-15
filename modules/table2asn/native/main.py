#!/usr/bin/env python3
"""table2asn native 标准入口驱动。

table2asn 是 NCBI 现役的 GenBank 提交文件生成工具，取代已停用（Obsolete）的 tbl2asn
（官方文档原文："table2asn is the replacement of the older now-obsolete tool tbl2asn"）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py wgs -t ecoli.sbt --indir ./ --validate-level vb
   python main.py complete -t Malassezia_sympodialis.sbt --indir ./ --outdir ./out
   python main.py validate -t ecoli.sbt --indir ./
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（统一模板，与官方文档的 WGS 示例一致）：
  table2asn -t <template.sbt> -indir <dir> [-outdir <dir>] [-i <x.fsa>] -a <type>
            [-l paired-ends] [-gaps-min <n>] -V <opt> -M n -Z [extra...]
子命令：wgs（-a r1k -l paired-ends）/ complete（-a a）/ validate（-V v）/ run（自行指定）。

⚠️ 与 tbl2asn 的参数差异（官方文档明示，务必注意）：
  -p <dir>      -> -indir <dir>    （输入目录）
  -r <dir>      -> -outdir <dir>   （.sqn 输出目录）
  -Z <file>     -> -Z              （不再接受文件名参数，仅作开关；产出 .dr 差异报告）
注意：table2asn 本体单线程，--threads 仅作统一接口与上层调度参考，不注入命令行。
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
    "wgs": "不完整基因组（WGS）提交：-a r1k -l paired-ends（产出 .sqn/.val/.stats/.dr）",
    "complete": "完整基因组（带注释）提交：-a a（产出 .sqn/.gbf）",
    "validate": "仅生成验证/差异报告：-V v -Z（不注入 -a）",
    "run": "通用调用：自行指定 --assembly-type/--validate-level/--paired-ends/--gaps-min/--input",
}

# 子命令 -> -a 默认值（None 表示不注入，由用户显式给出）
DEFAULT_ASSEMBLY_TYPE = {"wgs": "r1k", "complete": "a", "validate": None, "run": None}

# 官方安装渠道提示（缺二进制时报错信息，指向官方渠道）
_INSTALL_HINT = (
    "未找到可执行文件 'table2asn'，请先安装（官方渠道任选其一）：\n"
    "  1) Conda/bioconda：mamba create -n table2asn-native -c conda-forge -c bioconda table2asn=1.28.1179\n"
    "  2) 官方容器：docker pull quay.io/biocontainers/table2asn:1.28.1179--he45da00_1\n"
    "  3) 官方 FTP 预编译二进制：https://ftp.ncbi.nlm.nih.gov/toolbox/ncbi_tools/converters/by_program/table2asn/\n"
    "     （linux64.table2asn.gz / mac.table2asn.gz / win64.table2asn.zip；也可跑 native/install.sh）"
)


class Table2asnSkill(base.SkillBase):
    software = "table2asn"
    binary = "table2asn"

    def _resolve_binary(self) -> str:
        """惰性解析 table2asn 二进制；未安装时给出官方渠道安装提示。"""
        path = base.which(self.binary)
        if not path:
            raise RuntimeError(_INSTALL_HINT)
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 table2asn 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        # -t 模板 / -indir 输入目录 / -outdir 输出目录 / -i 单文件
        if kw.get("template"):
            cmd += ["-t", str(kw["template"])]
        if kw.get("indir"):
            cmd += ["-indir", str(kw["indir"])]
        if kw.get("outdir"):
            cmd += ["-outdir", str(kw["outdir"])]
        if kw.get("input"):
            cmd += ["-i", str(kw["input"])]

        # -a FASTA 类型（子命令预设，可被显式覆盖）
        assembly_type = kw.get("assembly_type") or DEFAULT_ASSEMBLY_TYPE.get(subcommand)
        if assembly_type:
            cmd += ["-a", str(assembly_type)]

        # -l paired-ends（WGS 默认开启）
        paired = kw.get("paired_ends")
        if paired is None:
            paired = subcommand == "wgs"
        if paired:
            cmd += ["-l", "paired-ends"]

        # -gaps-min 最小 gap 长度
        if kw.get("gaps_min") is not None:
            cmd += ["-gaps-min", str(kw["gaps_min"])]

        # -V 验证选项（validate 子命令默认仅 v）
        validate_level = kw.get("validate_level") or ("v" if subcommand == "validate" else "vb")
        cmd += ["-V", str(validate_level)]

        # -M master file 选项（默认 n）
        cmd += ["-M", str(kw.get("master_level") or "n")]

        # -Z 差异报告：table2asn 中为无参数开关（tbl2asn 时代写作 -Z discrep）
        cmd += ["-Z"]

        # 线程：table2asn 单线程，仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """table2asn 公共选项（-t/-indir/-outdir/-i/-a/-l/-gaps-min/-V/-M）。"""
    p.add_argument("-t", "--template", help="提交模板 .sbt（前缀需与 .fsa/.tbl 同名）")
    p.add_argument("--indir", help="输入目录（官方新参数，取代旧版 -p；当前目录写 --indir .）")
    p.add_argument("--outdir", help=".sqn 输出目录（官方新参数，取代旧版 -r）")
    p.add_argument("-i", "--input", dest="input", help="只提交指定的单个 .fsa 文件")
    p.add_argument("-a", "--assembly-type", dest="assembly_type",
                   help="FASTA 类型：a / r1k（WGS 默认）/ r1u / s")
    p.add_argument("-l", "--paired-ends", dest="paired_ends", action="store_true", default=None,
                   help="gap 连接证据为 paired-ends（wgs 默认开启；注入 -l paired-ends）")
    p.add_argument("--gaps-min", dest="gaps_min", type=int, help="最小 gap 长度（如 10）")
    p.add_argument("-V", "--validate-level", dest="validate_level",
                   help="验证选项：v / b / vb（默认 vb；validate 默认 v）")
    p.add_argument("-M", "--master-level", dest="master_level", help="master file 选项（默认 n）")
    p.add_argument("--extra-args", dest="extra_args", help="透传给 table2asn 的额外参数")


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（table2asn 单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="table2asn-skill",
        description="table2asn native 技能驱动（NCBI ASN.1 提交文件生成；tbl2asn 的现役后继）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    for name in SUBCOMMANDS:
        sp = sub.add_parser(name, help=SUBCOMMANDS[name])
        _add_common_opts(sp)
        _add_runtime_opts(sp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = Table2asnSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Table2asnSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        # 重新渲染 env_vars，确保 --tmpdir 真正注入到 TMPDIR
        skill.env_vars = skill._render_env_vars(
            (skill.meta.get("optimization", {}) or {}).get("env_vars", {})
        )

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
