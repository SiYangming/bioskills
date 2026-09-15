#!/usr/bin/env python3
"""prottest native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run allSingleCopyOrthologsAlign.phy -all-distributions -F -AIC -BIC -tc 0.5 --threads 4 -o prottest.out
   python main.py hpc allSingleCopyOrthologsAlign.phy -all-distributions -F -AIC -BIC --processes 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  run  java <JAVA_OPTS> -jar prottest-3.4.2.jar -i <aln> [-t <tree>] [-all-distributions] [-F] [-AIC] [-BIC] [-tc <x>] [-o <out>] -threads N
  hpc  bash <PROTTEST_HOME>/runProtTestHPC.sh <np> -i <aln> [... 同上，不含 -threads]
JVM 堆内存与临时目录经 JAVA_OPTS（optimization.env_vars，含 {tmpdir} 占位）透传。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
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
    "run": "序列版模型选择：java -jar prottest-3.4.2.jar -i <aln> -all-distributions -F -AIC -BIC -tc <x> -threads N",
    "hpc": "MPJ 并行模型选择：bash runProtTestHPC.sh <np> -i <aln> ...（需 MPJ Express）",
}

JAR_NAME = "prottest-3.4.2.jar"


class ProttestSkill(base.SkillBase):
    software = "prottest"
    binary = "java"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _java_prefix(self) -> list[str]:
        """java 可执行 + JAVA_OPTS（-Xmx / -Djava.io.tmpdir）组成的命令前缀。"""
        java = self._resolve_binary()
        opts = shlex.split(self.env_vars.get("JAVA_OPTS", ""))
        return [java, *opts, "-jar"]

    def _resolve_jar(self) -> str:
        """解析 prottest-3.4.2.jar：优先 $PROTTEST_JAR / $PROTTEST_HOME，其次常见安装位置。"""
        cands: list[Path] = []
        explicit = os.environ.get("PROTTEST_JAR")
        if explicit:
            cands.append(Path(explicit))
        home = os.environ.get("PROTTEST_HOME")
        if home:
            cands += [Path(home) / JAR_NAME, Path(home) / "dist" / JAR_NAME]
        cands += [
            Path.home() / "software" / "prottest-3.4.2" / JAR_NAME,
            Path.home() / "software" / "prottest-3.4.2" / "dist" / JAR_NAME,
            Path("/opt/prottest-3.4.2") / JAR_NAME,
        ]
        for cand in cands:
            if cand.is_file():
                return str(cand)
        raise RuntimeError(
            f"未找到 {JAR_NAME}；请将其放入安装目录或设置 PROTTEST_JAR / PROTTEST_HOME。"
            f"官方下载：https://github.com/ddarriba/prottest3/releases"
        )

    def _model_flags(self, kw: dict) -> list[str]:
        """构建模型选择通用参数（-i/-t/-all-distributions/-F/-AIC/-BIC/-tc/-o）。"""
        cmd: list[str] = []
        aln = kw.get("input") or kw.get("alignment")
        if not aln:
            raise ValueError("缺少必填参数 input（-i 氨基酸比对文件）")
        cmd += ["-i", str(aln)]
        if kw.get("tree"):
            cmd += ["-t", str(kw["tree"])]
        if kw.get("all_distributions", True):
            cmd.append("-all-distributions")
        if kw.get("empirical_freq", True):
            cmd.append("-F")
        if kw.get("aic", True):
            cmd.append("-AIC")
        if kw.get("bic", True):
            cmd.append("-BIC")
        if kw.get("aicc"):
            cmd.append("-AICC")
        if kw.get("tc") is not None:
            cmd += ["-tc", str(kw["tc"])]
        if kw.get("ncat") is not None:
            cmd += ["-ncat", str(kw["ncat"])]
        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        return cmd

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 java -jar / MPJ 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "run":
            cmd = self._java_prefix()
            cmd.append(self._resolve_jar())
            cmd += self._model_flags(kw)
            cmd += ["-threads", str(threads)]

        else:  # hpc
            jar = self._resolve_jar()
            script = Path(jar).parent / "runProtTestHPC.sh"
            if not script.is_file():
                raise RuntimeError(f"未找到官方并行脚本 runProtTestHPC.sh（期望: {script}）")
            np = kw.get("processes") or threads
            cmd = ["bash", str(script), str(np)]
            cmd += self._model_flags(kw)

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
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（run 注入 -threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 JAVA_OPTS -Djava.io.tmpdir）")


def _add_model_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加模型选择参数（run/hpc 共用）。"""
    p.add_argument("input", nargs="?", help="氨基酸多序列比对文件（别名 --input）")
    p.add_argument("-i", "--input", dest="input_flag", help="氨基酸比对文件（别名）")
    p.add_argument("-t", "--tree", help="起始树文件（Newick，可选）")
    p.add_argument("-o", "--output", help="结果输出文件（缺省 stdout）")
    p.add_argument("--no-all-distributions", dest="all_distributions", action="store_false",
                   help="不纳入 +G / +I+G 模型")
    p.add_argument("--no-F", dest="empirical_freq", action="store_false", help="不纳入经验频率模型")
    p.add_argument("--no-AIC", dest="aic", action="store_false", help="不按 AIC 排序")
    p.add_argument("--no-BIC", dest="bic", action="store_false", help="不按 BIC 排序")
    p.add_argument("--AICC", dest="aicc", action="store_true", help="额外按 AICc 排序")
    p.add_argument("-tc", type=float, help="共识树阈值（0.5~1.0）")
    p.add_argument("-ncat", type=int, help="+G / +I+G 速率分类数（默认 4）")
    p.add_argument("--extra-args", help="透传给 ProTest 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="prottest-skill",
        description="prottest native 技能驱动（ProtTest3 蛋白质模型选择；JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    _add_model_opts(pr)
    _add_runtime_opts(pr)

    ph = sub.add_parser("hpc", help=SUBCOMMANDS["hpc"])
    ph.add_argument("--processes", type=int, help="MPJ 进程数（缺省取线程数）")
    _add_model_opts(ph)
    _add_runtime_opts(ph)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = ProttestSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ProttestSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars = skill._render_env_vars(
            (skill.meta.get("optimization", {}) or {}).get("env_vars", {})
        )

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "input_flag") and v is not None}
    kw["threads"] = ns.threads
    if getattr(ns, "input_flag", None):
        kw["input"] = ns.input_flag

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
