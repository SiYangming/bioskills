#!/usr/bin/env python3
"""beast2（BEAST2 v2.5.2）native 标准入口驱动（Java CLI 驱动）。

BEAST2 官方发布物为预编译目录（beast/bin/{beast,beauti,treeannotator,logcombiner,
loganalyser,densitetree,...}），每个 launcher 内部仍以 `java -cp launcher.jar ...` 运行。
本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py beast input.xml --beagle --threads 8 --instances 8
   python main.py treeannotator input.trees -o tree_abbr.BEAST2 --burnin 20
   python main.py logcombiner a.log b.log -o combined.log --burnin 10
   python main.py version
2. Agent Function Calling / Schema 自省：--schema / --list-commands

优化：
- JVM 堆内存与临时目录经 JAVA_OPTS（-Xmx{mem_mb}m -Djava.io.tmpdir={tmpdir}）注入。
- beast 支持 -beagle 加速与 -threads；--threads 优先级：显式 > per_subcommand_threads > default_cpus。
- ⚠️ BEAST 2.5.2 需 Java 8/11（Java ≥20 移除 Thread.stop，会抛 UnsupportedOperationException）。
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
    "beast": "beast：运行 MCMC 贝叶斯分析（input.xml；可选 -beagle/-threads/-instances）",
    "treeannotator": "treeannotator：由 posterior tree 采样生成 MCC 树（-burnin input.trees output）",
    "logcombiner": "logcombiner：合并/降采样多个 .log / .trees（-b burnin -o out in1 in2 ...）",
    "loganalyser": "loganalyser：log 统计量摘要（-b burnin in1 in2 ...）",
    "densitetree": "densitetree：DensiTree 树分布可视化",
    "beauti": "beauti：BEAUti 图形界面（由比对/树生成 BEAST 输入 XML）",
    "version": "version：beast -version（打印 v2.5.2）",
}

# 子命令 -> 实际 launcher 文件名
_PROGRAM_BY_SUBCOMMAND = {
    "beast": "beast",
    "treeannotator": "treeannotator",
    "logcombiner": "logcombiner",
    "loganalyser": "loganalyser",
    "densitetree": "densitetree",
    "beauti": "beauti",
    "version": "beast",
}


class Beast2Skill(base.SkillBase):
    software = "beast2"
    binary = "beast"

    def _resolve_program(self, name: str) -> str:
        """按 launcher 名解析 BEAST2 可执行文件（惰性解析，测试可 monkeypatch）。"""
        path = shutil.which(name)
        if not path:
            raise RuntimeError(
                f"未找到 BEAST2 launcher '{name}'，请先安装（官方预编译包 BEAST.v2.5.2.Linux.tgz 用 "
                "native/install.sh；或 conda beast2 / brew brew tap brewsci/bio + brew install beast2）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        program = self._resolve_program(_PROGRAM_BY_SUBCOMMAND[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))
        extra = str(kw.get("extra_args") or "").split()

        if subcommand == "version":
            return [program, "-version"]

        if subcommand == "beast":
            inp = kw.get("input")
            if not inp:
                raise ValueError("beast 缺少必填参数 input（BEAST 输入 XML）")
            cmd: list[str] = [program]
            if kw.get("beagle"):
                cmd += ["-beagle", "-beagle_CPU", "-beagle_SSE", "-beagle_double"]
            if kw.get("instances"):
                cmd += ["-instances", str(kw["instances"])]
            cmd += ["-threads", str(threads)]
            cmd += extra
            cmd.append(str(inp))
            return cmd

        if subcommand == "treeannotator":
            inp = kw.get("input")
            if not inp:
                raise ValueError("treeannotator 缺少必填参数 input（posterior .trees）")
            out = kw.get("output") or f"{inp}.mcc.tre"
            cmd = [program, "-burnin", str(kw.get("burnin") or 10)]
            cmd += extra
            cmd += [str(inp), str(out)]
            return cmd

        if subcommand == "logcombiner":
            inputs = kw.get("inputs")
            if not inputs:
                raise ValueError("logcombiner 至少需要 1 个输入文件")
            items = inputs if isinstance(inputs, list) else [inputs]
            cmd = [program]
            if kw.get("burnin"):
                cmd += ["-b", str(kw["burnin"])]
            cmd += ["-o", str(kw.get("output") or "combined.log")]
            cmd += extra
            cmd += [str(i) for i in items]
            return cmd

        # loganalyser / densitetree
        inputs = kw.get("inputs") or kw.get("input")
        if not inputs:
            raise ValueError(f"{subcommand} 至少需要 1 个输入文件")
        items = inputs if isinstance(inputs, list) else [inputs]
        cmd = [program]
        if subcommand == "loganalyser" and kw.get("burnin"):
            cmd += ["-b", str(kw["burnin"])]
        if subcommand == "densitetree" and kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        cmd += extra
        cmd += [str(i) for i in items]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（beast 注入 -threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="beast2-skill",
        description="beast2（BEAST2 v2.5.2）native 技能驱动（JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pb = sub.add_parser("beast", help=SUBCOMMANDS["beast"])
    pb.add_argument("input", help="BEAST 输入 XML")
    pb.add_argument("--beagle", action="store_true", help="启用 BEAGLE 加速")
    pb.add_argument("--instances", type=int, help="BEAGLE 并行实例数")
    pb.add_argument("--extra-args", dest="extra_args", help="透传额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    pt = sub.add_parser("treeannotator", help=SUBCOMMANDS["treeannotator"])
    pt.add_argument("input", help="posterior .trees")
    pt.add_argument("-o", "--output", help="输出 MCC 树（默认 <input>.mcc.tre）")
    pt.add_argument("-b", "--burnin", type=int, help="丢弃的预热比例（%%）")
    pt.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pt)

    pl = sub.add_parser("logcombiner", help=SUBCOMMANDS["logcombiner"])
    pl.add_argument("inputs", nargs="+", help="输入 .log / .trees（可多个）")
    pl.add_argument("-o", "--output", help="合并输出（默认 combined.log）")
    pl.add_argument("-b", "--burnin", type=int, help="丢弃的预热比例（%%）")
    pl.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pl)

    pa = sub.add_parser("loganalyser", help=SUBCOMMANDS["loganalyser"])
    pa.add_argument("inputs", nargs="+", help="输入 .log（可多个）")
    pa.add_argument("-b", "--burnin", type=int, help="丢弃的预热比例（%%）")
    pa.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pa)

    pd = sub.add_parser("densitetree", help=SUBCOMMANDS["densitetree"])
    pd.add_argument("inputs", nargs="+", help="输入 .trees（可多个）")
    pd.add_argument("-o", "--output", help="输出图片")
    pd.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pd)

    pu = sub.add_parser("beauti", help=SUBCOMMANDS["beauti"])
    pu.add_argument("--extra-args", dest="extra_args", help="透传额外参数")
    _add_runtime_opts(pu)

    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = Beast2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Beast2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

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
