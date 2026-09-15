#!/usr/bin/env python3
"""jcvi native 标准入口驱动。

jcvi（MCscan Python 版）以 Python 包形态分发，无独立命令行二进制，统一以 `python -m jcvi...`
调用各子命令（用户环境中的 python 需已安装 jcvi）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py ortholog laame plost --cscore 0.5 --no-strip-names --threads 8
   python main.py dotplot laame.plost.anchors --title "Laccaria vs Pleurotus" -o dot.pdf
   python main.py karyotype seqids layout -o karyotype.pdf
   python main.py synteny blocks.bed laame.bed layout -o synteny.pdf
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐 jcvi 1.6.7 实际 CLI）：
  ortholog   python -m jcvi.compara.catalog ortholog <sp1> <sp2> [--cscore F] [--no_strip_names] [--cpus N]
  dotplot    python -m jcvi.graphics.dotplot <anchors> [--title S] [-o out]
  karyotype  python -m jcvi.graphics.karyotype <seqids> <layout> [-o out]
  synteny    python -m jcvi.graphics.synteny <blocks> <bed> <layout> [--outputprefix P]
线程经 --cpus 注入到 ortholog（优先级：--threads > per_subcommand_threads > default_cpus）。
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
    "ortholog": "jcvi.compara.catalog ortholog：LAST/BLAST + MCscan 计算共线性锚点（--cscore/--no_strip_names/--cpus）",
    "dotplot": "jcvi.graphics.dotplot：共线性点阵图",
    "karyotype": "jcvi.graphics.karyotype：共线性圈图/核型图（seqids + layout）",
    "synteny": "jcvi.graphics.synteny：微共线性图（blocks + bed + layout）",
}


class JcviSkill(base.SkillBase):
    software = "jcvi"
    binary = "python"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        # jcvi 以 python -m 驱动；解析当前 python 解释器（测试可 monkeypatch）
        python = self._resolve_binary()

        if subcommand == "ortholog":
            sp1, sp2 = kw.get("sp1"), kw.get("sp2")
            if not (sp1 and sp2):
                raise ValueError("ortholog 缺少必填参数 sp1、sp2（物种前缀）")
            cmd = [python, "-m", "jcvi.compara.catalog", "ortholog", str(sp1), str(sp2)]
            if kw.get("cscore") is not None:
                cmd += ["--cscore", str(kw["cscore"])]
            if kw.get("no_strip_names"):
                cmd += ["--no_strip_names"]
            # 线程优先级：显式 --threads > per_subcommand_threads.ortholog > default_cpus
            threads = self._effective_threads("ortholog", kw.get("threads"))
            cmd += ["--cpus", str(threads)]

        elif subcommand == "dotplot":
            anchors = kw.get("anchors")
            if not anchors:
                raise ValueError("dotplot 缺少必填参数 anchors（<sp1>.<sp2>.anchors）")
            cmd = [python, "-m", "jcvi.graphics.dotplot", str(anchors)]
            if kw.get("title"):
                cmd += ["--title", str(kw["title"])]
            if kw.get("outfile"):
                cmd += ["-o", str(kw["outfile"])]

        elif subcommand == "karyotype":
            seqids, layout = kw.get("seqids"), kw.get("layout")
            if not (seqids and layout):
                raise ValueError("karyotype 缺少必填参数 seqids、layout")
            cmd = [python, "-m", "jcvi.graphics.karyotype", str(seqids), str(layout)]
            if kw.get("outfile"):
                cmd += ["-o", str(kw["outfile"])]

        else:  # synteny
            blocks, bed, layout = kw.get("blocks"), kw.get("bed"), kw.get("layout")
            if not (blocks and bed and layout):
                raise ValueError("synteny 缺少必填参数 blocks、bed、layout")
            cmd = [python, "-m", "jcvi.graphics.synteny", str(blocks), str(bed), str(layout)]
            if kw.get("outputprefix"):
                cmd += ["--outputprefix", str(kw["outputprefix"])]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（ortholog 经 --cpus 注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="jcvi-skill",
        description="jcvi native 技能驱动（python -m jcvi...：ortholog/dotplot/karyotype/synteny）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    po = sub.add_parser("ortholog", help=SUBCOMMANDS["ortholog"])
    po.add_argument("sp1", help="物种 1 前缀")
    po.add_argument("sp2", help="物种 2 前缀")
    po.add_argument("--cscore", type=float, help="C-score 阈值（默认取 jcvi 内置 0.7）")
    po.add_argument("--no-strip-names", dest="no_strip_names", action="store_true",
                    help="不简化序列名称（jcvi --no_strip_names）")
    po.add_argument("--extra-args", help="透传给 jcvi 的额外参数")
    _add_runtime_opts(po)

    pd = sub.add_parser("dotplot", help=SUBCOMMANDS["dotplot"])
    pd.add_argument("anchors", help="共线性锚点文件（<sp1>.<sp2>.anchors）")
    pd.add_argument("--title", help="图标题")
    pd.add_argument("-o", "--outfile", help="输出图片路径")
    pd.add_argument("--extra-args", help="透传给 jcvi 的额外参数")
    _add_runtime_opts(pd)

    pk = sub.add_parser("karyotype", help=SUBCOMMANDS["karyotype"])
    pk.add_argument("seqids", help="染色体列表文件")
    pk.add_argument("layout", help="布局配置文件")
    pk.add_argument("-o", "--outfile", help="输出图片路径")
    pk.add_argument("--extra-args", help="透传给 jcvi 的额外参数")
    _add_runtime_opts(pk)

    py = sub.add_parser("synteny", help=SUBCOMMANDS["synteny"])
    py.add_argument("blocks", help="共线性 blocks 文件")
    py.add_argument("bed", help="BED 注释文件")
    py.add_argument("layout", help="布局配置文件")
    py.add_argument("--outputprefix", help="输出前缀")
    py.add_argument("--extra-args", help="透传给 jcvi 的额外参数")
    _add_runtime_opts(py)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = JcviSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = JcviSkill()
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
