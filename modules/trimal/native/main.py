#!/usr/bin/env python3
"""trimal native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py trim sample.aln -o sample.trimmed.aln            # 默认 -automated1
   python main.py trim sample.aln -o sample.trimmed.aln --method gt --gt-threshold 0.8
   python main.py readal sample.aln -o sample.phy --readal-format phylip
   python main.py statal sample.aln -o sample.stats.txt
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  trim     trimal -in <aln> -out <out> [-automated1 | -gt <x> | -gappyout | -strictplus | ...]
  readal   readal -in <aln> [-out <out>] [-<format>]
  statal   statal -in <aln> [-out <report>]
  version  trimal -h
trimAl 是单线程工具，--threads 仅作统一接口保留（不注入命令行）。
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
    "trim": "多序列比对 -> 修剪后比对（trimal -in <aln> -out <out>，默认 -automated1）",
    "readal": "比对格式转换（readal -in <aln> -out <out> -<format>）",
    "statal": "比对统计（statal -in <aln> -out <report>）",
    "version": "打印 trimAl 用法/版本（trimal -h）",
}

# 修剪策略 -> trimal 选项（gt 需配合阈值）
TRIM_METHODS = {
    "automated1": "-automated1",
    "gappyout": "-gappyout",
    "strict": "-strict",
    "strictplus": "-strictplus",
    "noallgaps": "-noallgaps",
    "gt": "-gt",
}


class TrimalSkill(base.SkillBase):
    software = "trimal"
    binary = "trimal"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        trimAl 为单线程工具，本值仅用于统一接口/日志，不注入命令行。
        """
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_tool(self, name: str) -> str:
        """惰性解析 trimal/readal/statal 之一（测试可 monkeypatch）。"""
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 trimAl。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 trimal/readal/statal 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        input_ = kw.get("input")
        output = kw.get("output")

        if subcommand == "version":
            return [self._resolve_tool("trimal"), "-h"]

        if not input_:
            raise ValueError(f"{subcommand} 缺少必填参数 input（多序列比对文件）")

        if subcommand == "trim":
            cmd = [self._resolve_tool("trimal"), "-in", str(input_)]
            if output:
                cmd += ["-out", str(output)]
            method = kw.get("method") or "automated1"
            if method == "gt":
                cmd.append("-gt")
                if kw.get("gt_threshold") is not None:
                    cmd.append(str(kw["gt_threshold"]))
            elif method in TRIM_METHODS:
                cmd.append(TRIM_METHODS[method])
            else:
                raise ValueError(f"未知 trim 策略: {method}（可选 {sorted(TRIM_METHODS)}）")

        elif subcommand == "readal":
            cmd = [self._resolve_tool("readal"), "-in", str(input_)]
            if output:
                cmd += ["-out", str(output)]
            fmt = kw.get("readal_format")
            if fmt:
                cmd.append(f"-{fmt}")

        else:  # statal
            cmd = [self._resolve_tool("statal"), "-in", str(input_)]
            if output:
                cmd += ["-out", str(output)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="trimal-skill",
        description="trimal native 技能驱动（MSA 修剪 / 格式转换 / 统计；单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # trim
    pt = sub.add_parser("trim", help=SUBCOMMANDS["trim"])
    pt.add_argument("input", help="输入多序列比对")
    pt.add_argument("-o", "--output", help="输出修剪后比对路径（缺省写 stdout）")
    pt.add_argument("-m", "--method", choices=sorted(TRIM_METHODS), default="automated1",
                    help="修剪策略（默认 automated1；gt 需配合 --gt-threshold）")
    pt.add_argument("--gt-threshold", type=float, help="method=gt 时的 gap 阈值（0–1）")
    pt.add_argument("--extra-args", help="透传给 trimal 的额外参数")
    _add_runtime_opts(pt)

    # readal
    pr = sub.add_parser("readal", help=SUBCOMMANDS["readal"])
    pr.add_argument("input", help="输入多序列比对")
    pr.add_argument("-o", "--output", help="输出转换后比对路径")
    pr.add_argument("--readal-format",
                    choices=["fasta", "phylip", "clustal", "nexus", "pir", "phylip3.2",
                             "mega", "nbrf", "pdb", "msf", "gcg"],
                    help="readal 输出格式（映射 -<format>）")
    pr.add_argument("--extra-args", help="透传给 readal 的额外参数")
    _add_runtime_opts(pr)

    # statal
    ps = sub.add_parser("statal", help=SUBCOMMANDS["statal"])
    ps.add_argument("input", help="输入多序列比对")
    ps.add_argument("-o", "--output", help="输出统计报告路径（缺省写 stdout）")
    ps.add_argument("--extra-args", help="透传给 statal 的额外参数")
    _add_runtime_opts(ps)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（trimAl 单线程，仅接口保留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = TrimalSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TrimalSkill()
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

    # trim/statal 未给 -o 时把 stdout 落到 output（若指定）；否则原样回显
    if result.stdout and not getattr(ns, "output", None):
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
