#!/usr/bin/env python3
"""ninja（NINJA，Nearly Infinite Neighbor Joining Application）native 标准入口驱动。

NINJA（TravisWheelerLab）是大规模邻居合并（NJ）与单链接聚类工具；cluster_only 版主命令为
Ninja，按成对进化距离做单链接聚类（--out_type c，默认），也可输出距离矩阵（--out_type d）。
NINJA 是 RepeatModeler 的重复序列聚类依赖（多数场景由 modules/repeatmodeler 调用）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py cluster -i repeats.fa -o clusters.tsv --cluster_cutoff 0.03 --threads 8
   python main.py cluster -i aln.fa -o dist.phy --out_type d
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

Ninja 真实 CLI（以 `Ninja -h` 为准，版本 1.00-cluster_only）：
   Ninja --in file.fa --out file.out
   --in/-i <file> / --out/-o <file>
   --in_type [a|d]（默认 a） / --out_type [d|c]（默认 c）
   --corr_type [n|j|k|s|m] / --cluster_cutoff <dist>（默认 0.03）
   --threads/-T <n> / --version/-v
所有子命令自动注入线程（--threads/-T）与临时目录（TMPDIR 环境变量）。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "cluster": "Ninja：比对 FASTA / 距离矩阵 → 单链接聚类（--out_type c，默认）或距离矩阵（--out_type d）",
}

IN_TYPES = ("a", "d")
OUT_TYPES = ("c", "d")
CORR_TYPES = ("n", "j", "k", "s", "m")


class NinjaSkill(base.SkillBase):
    software = "ninja"
    binary = "Ninja"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/ninja/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_ninja(self) -> str:
        """解析 Ninja 可执行文件，找不到时给出官方 conda/容器安装指引。"""
        path = shutil.which(self.binary or self.software)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'Ninja'：NINJA（cluster_only 版）主命令名为 Ninja。"
                "请先安装官方包（bioconda 包名 ninja-nj，注意不是同名构建系统 conda-forge/ninja）："
                "mamba create -n ninja -c conda-forge -c bioconda ninja-nj=1.00（或 "
                "docker pull quay.io/biocontainers/ninja-nj:1.00--h9948957_1），"
                "亦可 bash native/install.sh（conda / 源码编译双路线）。"
                "NINJA 是 RepeatModeler 的重复聚类依赖，多数场景由 modules/repeatmodeler 调用。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 Ninja 命令行（真实 CLI 见模块头注）。"""
        if subcommand != "cluster":
            raise RuntimeError(f"未知子命令: {subcommand}")

        inp = kw.get("input")
        if not inp:
            raise RuntimeError("cluster 需要 --input/-i（输入比对 FASTA 或距离矩阵）")
        out = kw.get("output")
        if not out:
            raise RuntimeError("cluster 需要 --output/-o（输出聚类表或距离矩阵）")

        binary = self._resolve_ninja()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        # Ninja 原生参数：--in/-i、--out/-o、--threads/-T
        cmd: list[str] = [binary, "-i", str(inp), "-o", str(out), "-T", str(threads)]

        in_type = kw.get("in_type")
        if in_type:
            in_type = str(in_type).lower()
            if in_type not in IN_TYPES:
                raise RuntimeError(f"--in_type 仅支持 a|d（收到: {in_type}）")
            cmd += ["--in_type", in_type]

        out_type = kw.get("out_type")
        if out_type:
            out_type = str(out_type).lower()
            if out_type not in OUT_TYPES:
                raise RuntimeError(f"--out_type 仅支持 c|d（收到: {out_type}）")
            cmd += ["--out_type", out_type]

        corr_type = kw.get("corr_type")
        if corr_type:
            corr_type = str(corr_type).lower()
            if corr_type not in CORR_TYPES:
                raise RuntimeError(f"--corr_type 仅支持 n|j|k|s|m（收到: {corr_type}）")
            cmd += ["--corr_type", corr_type]

        cutoff = kw.get("cluster_cutoff")
        if cutoff is not None:
            cmd += ["--cluster_cutoff", str(cutoff)]

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
        prog="ninja-skill",
        description="ninja（NINJA cluster_only 版 Ninja）native 技能驱动（序列聚类 / 距离矩阵；自动注入线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # cluster: Ninja --in <file> --out <file> [--in_type a|d] [--out_type c|d] ...
    pc = sub.add_parser("cluster", help=SUBCOMMANDS["cluster"])
    pc.add_argument("-i", "--input", required=True,
                    help="输入文件（比对 FASTA 或 Phylip 距离矩阵；Ninja --in）")
    pc.add_argument("-o", "--output", required=True,
                    help="输出文件（聚类表或距离矩阵；Ninja --out）")
    # 同时接受下划线（Ninja 原生）与连字符形式
    pc.add_argument("--in_type", "--in-type", dest="in_type", choices=IN_TYPES,
                    help="输入类型：a（比对 FASTA，默认）| d（距离矩阵）")
    pc.add_argument("--out_type", "--out-type", dest="out_type", choices=OUT_TYPES,
                    help="输出类型：c（单链接聚类，默认）| d（距离矩阵）")
    pc.add_argument("--corr_type", "--corr-type", dest="corr_type", choices=CORR_TYPES,
                    help="距离校正类型（可选）：n|j|k|s|m")
    pc.add_argument("--cluster_cutoff", "--cluster-cutoff", dest="cluster_cutoff", type=float,
                    help="单链接聚类距离阈值（默认 0.03，仅 --out_type c 时生效）")
    pc.add_argument("--extra-args", dest="extra_args",
                    help="透传给 Ninja 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 Ninja --threads/-T）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = NinjaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = NinjaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
