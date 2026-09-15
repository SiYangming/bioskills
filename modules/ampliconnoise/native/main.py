#!/usr/bin/env python3
"""ampliconnoise native 标准入口驱动（AmpliconNoise V1.27；说明型）。

AmpliconNoise 是 454 焦磷酸测序时代的扩增子**去噪 / 嵌合体检测**程序集
（Quince C et al. BMC Bioinformatics 2011;12:38），历史上由 QIIME 1 通过 qiime-deploy 部署。
所有程序均为 **MPI 程序**，需 `make && make install` 编译（依赖 mpicc），运行时以 `mpirun -np N` 启动。

本驱动为「说明型 + 命令构造」：按各程序用法构造命令行（默认补 `mpirun -np <N>`）并打印，
**不实际执行**（历史工具 + MPI），供 454 去噪流程复现 / 文档化调用 / Agent 展示。覆盖 12 个程序：
  PyroNoise · PyroNoiseM · PyroDist · SeqNoise · SeqDist · NDist · FCluster ·
  FastaUnique · SplitClusterEven · SplitClusterClust · Perseus · PerseusD

两种调用模式：
1. CLI 直跑（人类 / Shell；程序参数原样透传）：
   python main.py PyroNoise -s 454Reads.sff -d ./Data --threads 8
   python main.py PerseusD --threads 8 <clustered.fasta>
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的程序

线程：AmpliconNoise 各程序均为 MPI 程序，线程即 MPI 进程数，构造为 `mpirun -np <n> <program>`。
临时目录经进程 TMPDIR 环境变量注入。
前置：已编译安装 AmpliconNoise V1.27（各程序在 PATH，见 README「环境安装」）。
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

# 子命令（程序名）语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "PyroNoise": "454 焦磷酸测序数据去噪主程序（-s sff -d data_dir -o out_dir）",
    "PyroNoiseM": "PyroNoise 改进版（含待测序错误模型）",
    "PyroDist": "计算去噪序列间距离",
    "SeqNoise": "去噪后序列的进一步去噪",
    "SeqDist": "计算去噪后序列距离",
    "NDist": "计算核苷酸（核苷酸级）距离",
    "FCluster": "按距离阈值聚类",
    "FastaUnique": "FASTA 去冗余 / 统计唯一序列",
    "SplitClusterEven": "按均分策略拆分聚类",
    "SplitClusterClust": "按聚类拆分",
    "Perseus": "嵌合体检测（基于距离的 Perseus 流程）",
    "PerseusD": "嵌合体检测（de novo PerseusD）",
}

# 历史工具提示（stderr，不干扰 stdout 产物）
HISTORICAL_NOTE = (
    "⚠️ AmpliconNoise（454 时代，2011）为历史工具：依赖 MPI、需源码 make 编译；原 Google Code 站已死，"
    "功能上已被 DADA2 / Deblur（ASV 去噪，见 qiime2 模块）取代。以下命令构造仅供复现历史 454 去噪流程。"
)


class AmpliconNoiseSkill(base.SkillBase):
    software = "ampliconnoise"

    def _resolve_program(self, subcommand: str) -> str:
        """按子命令解析程序可执行文件（PyroNoise 等），找不到会抛错。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        path = base.which(subcommand)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{subcommand}'：请先编译安装 AmpliconNoise V1.27 并把其 bin 目录加入 "
                f"PATH（见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """按 AmpliconNoise 程序用法构造（不执行）命令行，默认补 mpirun -np <N>。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        program_path = self._resolve_program(subcommand)
        threads = self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = ["mpirun", "-np", str(threads), program_path]

        extra = kw.get("args") or []
        if isinstance(extra, str):
            extra = extra.split()
        cmd += [str(a) for a in extra]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ampliconnoise-skill",
        description="ampliconnoise native 技能驱动（V1.27，说明型：构造 MPI 程序命令，服务于历史 454 去噪流程）",
        allow_abbrev=False,
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的程序")
    sub = p.add_subparsers(dest="subcommand", metavar="<program>")
    for name, desc in SUBCOMMANDS.items():
        sp = sub.add_parser(name, help=desc, description=desc, allow_abbrev=False)
        sp.add_argument("args", nargs="*", help="程序参数（原样透传）")
        _add_runtime_opts(sp)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程=MPI 进程数/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认 MPI 进程数（mpirun -np）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _split_runtime_opts(tokens: list[str]) -> tuple[list[str], int | None, str | None]:
    """从子命令后的 token 中抽出 --threads/--tmpdir，其余程序参数保持原始顺序。"""
    rest: list[str] = []
    threads: int | None = None
    tmpdir: str | None = None
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "--threads" and i + 1 < len(tokens):
            threads = int(tokens[i + 1]); i += 2; continue
        if t.startswith("--threads="):
            threads = int(t.split("=", 1)[1]); i += 1; continue
        if t == "--tmpdir" and i + 1 < len(tokens):
            tmpdir = tokens[i + 1]; i += 2; continue
        if t.startswith("--tmpdir="):
            tmpdir = t.split("=", 1)[1]; i += 1; continue
        rest.append(t)
        i += 1
    return rest, threads, tmpdir


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        width = max(len(k) for k in SUBCOMMANDS)
        for k, v in SUBCOMMANDS.items():
            print(f"{k:{width}s}  {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(AmpliconNoiseSkill().schema(), indent=2, ensure_ascii=False))
        return 0

    if not args or args[0] in ("-h", "--help"):
        build_parser().print_help(sys.stdout if args else sys.stderr)
        return 0 if args else 2

    subcommand, rest = args[0], args[1:]
    if subcommand not in SUBCOMMANDS:
        print(f"[ERROR] 未知子命令: {subcommand}（--list-commands 查看支持的程序）", file=sys.stderr)
        return 2

    action_args, threads, tmpdir = _split_runtime_opts(rest)
    skill = AmpliconNoiseSkill()
    if tmpdir:
        skill.tmpdir = tmpdir
        skill.env_vars["TMPDIR"] = tmpdir

    print(HISTORICAL_NOTE, file=sys.stderr)

    try:
        cmd = skill.build_command(subcommand, args=action_args, threads=threads)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print("构造命令（不执行；历史工具仅供复现，请人工核对后运行）：")
    print("  " + " \\\n    ".join(cmd))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
