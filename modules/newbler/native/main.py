#!/usr/bin/env python3
"""newbler native 标准入口驱动（Newbler 2.9 / GS De Novo Assembler；说明型）。

⚠️ DEPRECATED：本模块登记的是 Roche / 454 Life Sciences 的 454 组装器 Newbler
（gsAssembler，DataAnalysis_2.9_All）。454 测序平台已停产、Roche 关闭 454 业务，
Newbler 停止更新；官网 454.com 2026-09 已停服（software-request.asp 仅为跳转占位页）。
454 组装请改用 SPAdes / SOAPdenovo2 / MaSuRa 等替代工具。

本驱动为「说明型 + 命令构造」：不实际运行 Newbler（软件已淘汰、官网停服、无新用场景），
按官方命令语义构造命令行，供历史复现 / 文档化调用 / Agent 展示：
1. assemble：runAssembly -o <outdir> -force -tr <reads.sff>
2. map     ：runMapping -o <outdir> -force -tr <reads.sff> <reference.fasta>

两种调用模式：
1. CLI 直跑（人类 / Shell；仅打印构造命令，不执行）：
   python main.py assemble -r 454Reads.sff -o ./
   python main.py map -r 454Reads.sff -R ref.fasta -o ./
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
"""

from __future__ import annotations

import argparse
import json
import os
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
    "assemble": "454 de novo 组装（runAssembly -o <outdir> -force -tr <reads.sff>；命令构造）",
    "map": "454 读取回贴参考（runMapping -o <outdir> -force -tr <reads.sff> <ref.fasta>；命令构造）",
}

# 子命令 -> 真实可执行名（Newbler 2.9 下即此名，位于安装目录 bin/）
_BINARIES = {"assemble": "runAssembly", "map": "runMapping"}

DEPRECATED_NOTE = (
    "⚠️ Newbler 已淘汰（454 测序停产、Roche 关闭 454 业务、官网 454.com 停服，建议用 "
    "SPAdes / SOAPdenovo2 替代）：本模块仅作历史参考登记，以下命令构造仅供复现 2010 "
    "年代 454 组装分析，新项目请用现代短读组装器。"
)


class NewblerSkill(base.SkillBase):
    software = "newbler"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析可执行文件（runAssembly / runMapping），找不到会抛错。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：Newbler 已淘汰且官方分发点停服，"
                f"需自备 DataAnalysis_2.9_All 安装包并 ./setup.sh（见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """assemble / map：构造（不执行）历史 Newbler 命令行。"""
        bin_path = self._resolve_sub_binary(subcommand)
        reads = kw.get("reads")
        if not reads:
            raise RuntimeError(f"{subcommand} 需要输入 reads（-r/--reads，454 SFF 文件）")

        outdir = kw.get("output_dir") or "./"
        cmd: list[str] = [bin_path, "-o", str(outdir)]
        if kw.get("force", True):
            cmd.append("-force")
        if kw.get("trimmed", True):
            cmd.append("-tr")
        cmd.append(self._abspath(reads))

        if subcommand == "map":
            reference = kw.get("reference")
            if not reference:
                raise RuntimeError("map 需要参考序列（-R/--reference，FASTA）")
            cmd.append(self._abspath(reference))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="newbler-skill",
        description="Newbler native 技能驱动（说明型：构造历史 runAssembly/runMapping "
                    "命令，已淘汰，仅供历史参考）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("-r", "--reads", required=True, help="输入 454 reads（SFF，如 454Reads.sff）")
    pa.add_argument("-o", "--output-dir", default="./", help="输出目录（默认 ./）")
    pa.add_argument("--no-force", dest="force", action="store_false", help="不传 -force")
    pa.add_argument("--no-trimmed", dest="trimmed", action="store_false", help="不使用 trimmed reads（不传 -tr）")
    pa.add_argument("--extra-args", help="透传给 runAssembly 的额外参数")
    _add_runtime_opts(pa)

    pm = sub.add_parser("map", help=SUBCOMMANDS["map"])
    pm.add_argument("-r", "--reads", required=True, help="输入 454 reads（SFF，如 454Reads.sff）")
    pm.add_argument("-R", "--reference", required=True, help="参考序列 FASTA")
    pm.add_argument("-o", "--output-dir", default="./", help="输出目录（默认 ./）")
    pm.add_argument("--no-force", dest="force", action="store_false", help="不传 -force")
    pm.add_argument("--no-trimmed", dest="trimmed", action="store_false", help="不使用 trimmed reads（不传 -tr）")
    pm.add_argument("--extra-args", help="透传给 runMapping 的额外参数")
    _add_runtime_opts(pm)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="线程数（Newbler 无 --threads 旗标，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = NewblerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = NewblerSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir")}
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
