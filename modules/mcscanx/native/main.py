#!/usr/bin/env python3
"""mcscanx native 标准入口驱动。

MCScanX 以「输入前缀」方式运行：MCScanX <prefix> 读取 <prefix>.blast（BLAST/DIAMOND m8 比对）
与 <prefix>.gff（基因位置），输出 <prefix>.collinearity / <prefix>.html。配套组件：
duplicate_gene_classifier（基因类型鉴定）、downstream_analyses 下的 dual_synteny_plotter 与
circle_plotter（Java 绘图，用法 `java <class> -g ... -s ... -c ... -o ...`）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py scan data/input
   python main.py classify data/input
   python main.py dual -g data/nc_cp.gff -s data/nc_cp.collinearity -c control -o data/nc_cp.dual.png
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

说明：MCScanX 本体为单线程 C++ 程序；每个子命令接受 --threads 仅为接口统一（并行体现在上游
      DIAMOND/BLAST all-vs-all 步骤）；Java 绘图的内存调优走 JAVA_OPTS。
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
    "scan": "MCScanX <prefix> 检测共线性区块（输入 <prefix>.blast + <prefix>.gff）",
    "classify": "duplicate_gene_classifier <prefix> 基因类型鉴定（singleton/dispersed/proximal/tandem/WGD）",
    "dual": "java dual_synteny_plotter 种间共线性图（-g/-s/-c/-o）",
    "circle": "java circle_plotter 种内共线性圈图（-g/-s/-c/-o）",
}


class McscanxSkill(base.SkillBase):
    software = "mcscanx"
    binary = "MCScanX"

    def _resolve_tool(self, name: str) -> str:
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 mcscanx（绘图组件需 JDK）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        prefix = kw.get("prefix") or kw.get("input")

        if subcommand == "scan":
            if not prefix:
                raise ValueError("scan 缺少必填参数 prefix（输入前缀，读取 <prefix>.blast + <prefix>.gff）")
            cmd = [self._resolve_binary(), str(prefix)]

        elif subcommand == "classify":
            if not prefix:
                raise ValueError("classify 缺少必填参数 prefix（输入前缀）")
            cmd = [self._resolve_tool("duplicate_gene_classifier"), str(prefix)]

        else:  # dual / circle：java <class> -g -s -c -o
            gff, collinearity, control, output = (
                kw.get("gff"), kw.get("collinearity"), kw.get("control"), kw.get("output"),
            )
            if not (gff and collinearity and control and output):
                raise ValueError(f"{subcommand} 需要 --gff、--collinearity、--control、--output 四个参数")
            java = self._resolve_tool("java")
            klass = "dual_synteny_plotter" if subcommand == "dual" else "circle_plotter"
            cmd = [java, klass, "-g", str(gff), "-s", str(collinearity),
                   "-c", str(control), "-o", str(output)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（MCScanX 本体单线程，仅为接口统一）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mcscanx-skill",
        description="mcscanx native 技能驱动（MCScanX 共线性检测 + 基因类型鉴定 + Java 绘图）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    ps = sub.add_parser("scan", help=SUBCOMMANDS["scan"])
    ps.add_argument("prefix", nargs="?", help="输入前缀（读取 <prefix>.blast + <prefix>.gff）")
    ps.add_argument("--extra-args", help="透传给 MCScanX 的额外参数")
    _add_runtime_opts(ps)

    pc = sub.add_parser("classify", help=SUBCOMMANDS["classify"])
    pc.add_argument("prefix", nargs="?", help="输入前缀（读取 <prefix>.blast + <prefix>.gff）")
    pc.add_argument("--extra-args", help="透传给 duplicate_gene_classifier 的额外参数")
    _add_runtime_opts(pc)

    for name in ("dual", "circle"):
        pd = sub.add_parser(name, help=SUBCOMMANDS[name])
        pd.add_argument("-g", "--gff", required=True, help="基因位置文件")
        pd.add_argument("-s", "--collinearity", required=True, help="共线性文件（<prefix>.collinearity）")
        pd.add_argument("-c", "--control", required=True, help="绘图控制文件")
        pd.add_argument("-o", "--output", required=True, help="输出图片路径")
        _add_runtime_opts(pd)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = McscanxSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = McscanxSkill()
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
