#!/usr/bin/env python3
"""trimmomatic native 标准入口驱动。

Trimmomatic 是 Java 程序，CLI 形如：
    java -jar trimmomatic-<ver>.jar PE|SE [-threads N] [-phred33|-phred64] ... <in...> <out...> <step>...
conda / brew / biocontainer 会额外提供一个 `trimmomatic` launcher（内部仍调 java），
等价能力也可直接 `trimmomatic PE ...` 调用。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py pe R1.fq.gz R2.fq.gz out_P1.fq.gz out_U1.fq.gz out_P2.fq.gz out_U2.fq.gz \
       "ILLUMINACLIP:adapters/TruSeq3-PE.fa:2:30:10" LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36
   python main.py se input.fq.gz output.fq.gz "ILLUMINACLIP:TruSeq3-SE.fa:2:30:10" LEADING:3 TRAILING:3 MINLEN:36
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- 定位 launcher：优先 PATH 上 `trimmomatic`（bioconda/brew/容器 wrapper）；否则
  TRIMMOMATIC_JAR 环境变量 → conda share / ~/software 常见位置的 trimmomatic-*.jar，
  以 `java -jar <jar>` 调用（需宿主 java 8+）。
- JVM 堆内存与临时目录经 JAVA_TOOL_OPTIONS / TMPDIR 注入（JVM 自动读取 JAVA_TOOL_OPTIONS，
  meta.yaml optimization.env_vars 用 {mem_mb}/{tmpdir} 占位符渲染）。
- -threads 自动注入（PE 默认 4 / SE 默认 2，可 --threads 覆盖）。
- ILLUMINACLIP 步骤若只给裸 adapter 文件名，自动在 jar 同侧 adapters/、conda share、
  cwd 中定位补全路径（0.39 需要完整路径；v0.40+ 官方已支持自动发现）。
- --dry-run 仅构造并打印 argv（不执行），供降级 argv 构造回归。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shlex
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "pe": "PE 双端修剪：R1 R2 -> paired/unpaired 4 个输出（去接头/低质量/短 reads）",
    "se": "SE 单端修剪：单端 FASTQ -> 输出（去接头/低质量/短 reads）",
}

# 常见 jar 位置探测（launcher 缺失时的兜底；均为用户级/conda 前缀，不写 /opt/biosoft）
_JAR_GLOBS = [
    "TRIMMOMATIC_JAR",  # 环境变量（绝对路径）
    "{conda}/share/trimmomatic*/trimmomatic-*.jar",
    "~/software/Trimmomatic-*/trimmomatic-*.jar",
    "~/software/trimmomatic*/trimmomatic-*.jar",
]


def _expand_jar_candidates() -> list[str]:
    """按优先级展开 jar 候选路径（含环境变量 TRIMMOMATIC_JAR 与常见安装位置）。"""
    cands: list[str] = []
    env_jar = os.environ.get("TRIMMOMATIC_JAR")
    if env_jar:
        cands.append(env_jar)
    conda = os.environ.get("CONDA_PREFIX", "")
    for pat in _JAR_GLOBS[1:]:
        p = pat.format(conda=conda)
        if p.startswith("~"):
            p = str(Path(p).expanduser())
        cands.append(p)
    return cands


class TrimmomaticSkill(base.SkillBase):
    software = "trimmomatic"
    binary = "trimmomatic"

    # -- launcher 解析 ------------------------------------------------------ #
    def _locate_jar(self) -> str | None:
        for c in _expand_jar_candidates():
            hits = sorted(glob.glob(c))
            if hits:
                return hits[0]
        return None

    def _resolve_launcher(self) -> list[str] | None:
        """返回命令前缀：['/path/trimmomatic'] 或 ['java', '-jar', jar]；找不到返回 None。"""
        wrapper = base.which("trimmomatic")
        if wrapper:
            return [wrapper]
        jar = self._locate_jar()
        if jar:
            java = base.which("java")
            if not java:
                raise RuntimeError(
                    "已定位 trimmomatic jar 但 PATH 中无 java；请先安装 Java 8+（conda: "
                    "mamba install -n <env> -c conda-forge openjdk）"
                )
            return [java, "-jar", jar]
        return None

    def _resolve_adapter_path(self, step: str) -> str:
        """ILLUMINACLIP 步骤只给裸 adapter 文件名时，尝试补全为绝对路径（0.39 需完整路径）。"""
        if not step.startswith("ILLUMINACLIP:") or ":" not in step[len("ILLUMINACLIP:"):]:
            return step
        rest = step[len("ILLUMINACLIP:"):]
        name = rest.split(":", 1)[0]
        if "/" in name or "\\" in name:  # 已是路径
            return step
        if Path(name).exists():  # cwd 下存在
            return step
        # 候选目录：jar/launcher 同侧 adapters、conda share、cwd/adapters
        roots: list[Path] = []
        wrapper = base.which("trimmomatic")
        if wrapper:
            roots.append(Path(wrapper).resolve().parent / ".." / "share")
            roots.append(Path(wrapper).resolve().parent)
        jar = self._locate_jar()
        if jar:
            roots.append(Path(jar).resolve().parent / "adapters")
            roots.append(Path(jar).resolve().parent)
        conda = os.environ.get("CONDA_PREFIX")
        if conda:
            roots += [Path(conda) / "share", Path(conda) / "share" / "trimmomatic" / "adapters"]
        roots.append(Path.cwd() / "adapters")
        for r in roots:
            hit = r / name
            if hit.exists():
                idx = rest.find(":")
                if idx != -1:
                    return f"ILLUMINACLIP:{hit}:{rest[idx + 1:]}"
                return f"ILLUMINACLIP:{hit}"
        return step  # 找不到则原样透传（由 trimmomatic 报错提示）

    # -- 命令构建 ---------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        # PE/SE 模式参数
        if subcommand == "pe":
            fwd = kw.get("fwd")
            rev = kw.get("rev")
            out_pf = kw.get("out_fwd_paired")
            out_uf = kw.get("out_fwd_unpaired")
            out_pr = kw.get("out_rev_paired")
            out_ur = kw.get("out_rev_unpaired")
            missing = [n for n, v in [
                ("fwd(R1)", fwd), ("rev(R2)", rev), ("out_fwd_paired", out_pf),
                ("out_fwd_unpaired", out_uf), ("out_rev_paired", out_pr),
                ("out_rev_unpaired", out_ur)] if not v]
            if missing:
                raise ValueError(f"pe 缺少必填参数: {', '.join(missing)}")
            mode = "PE"
            files = [fwd, rev, out_pf, out_uf, out_pr, out_ur]
        else:  # se
            fin = kw.get("input") or kw.get("fwd")
            fout = kw.get("output")
            if not fin or not fout:
                raise ValueError("se 缺少必填参数 input / output")
            mode = "SE"
            files = [fin, fout]

        steps = kw.get("steps") or []
        if isinstance(steps, str):
            steps = [steps]
        steps = [s for s in steps if s]
        if not steps:
            raise ValueError(
                "至少需要 1 个修剪步骤参数（如 \"ILLUMINACLIP:adapters/TruSeq3-PE.fa:2:30:10\" "
                "LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36）"
            )

        # 组装（无 launcher 时先给占位名 trimmomatic，run 时再解析真身）
        cmd: list[str] = []
        if kw.get("launcher") is not None:
            cmd += list(kw["launcher"])
        elif not kw.get("dry_run"):
            launcher = self._resolve_launcher()
            if launcher is None:
                raise RuntimeError(
                    "未找到 trimmomatic launcher 或 trimmomatic-*.jar；请先安装："
                    "conda/mamba（bioconda::trimmomatic）或官方 zip（native/install.sh，"
                    "或 export TRIMMOMATIC_JAR=/path/to/trimmomatic-0.39.jar）"
                )
            cmd += launcher
        else:
            cmd.append("trimmomatic")

        cmd.append(mode)
        # -threads 等选项必须位于文件参数之前（官方 CLI 语法）
        cmd += ["-threads", str(threads)]
        if kw.get("phred33"):
            cmd.append("-phred33")
        elif kw.get("phred64"):
            cmd.append("-phred64")
        if kw.get("trimlog"):
            cmd += ["-trimlog", str(kw["trimlog"])]
        if kw.get("summary"):
            cmd += ["-summary", str(kw["summary"])]

        cmd += [str(f) for f in files]
        for s in steps:
            cmd.append(self._resolve_adapter_path(str(s)))
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行（真实运行时才解析 launcher）。"""
        launcher = self._resolve_launcher()
        if launcher is None:
            raise RuntimeError(
                "未找到 trimmomatic launcher 或 trimmomatic-*.jar；请先安装：conda/mamba"
                "（bioconda::trimmomatic）或官方 zip（native/install.sh），"
                "或 export TRIMMOMATIC_JAR=/path/to/trimmomatic-0.39.jar"
            )
        args = self.build_command(subcommand, launcher=launcher, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="trimmomatic-skill",
        description="trimmomatic native 技能驱动（JVM 堆内存 -Xmx / -threads / TMPDIR 自动优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # pe：R1 R2 + 4 个输出（paired/unpaired × fwd/rev）
    pa = sub.add_parser("pe", help=SUBCOMMANDS["pe"])
    pa.add_argument("fwd", help="R1 输入 FASTQ(.gz)")
    pa.add_argument("rev", help="R2 输入 FASTQ(.gz)")
    pa.add_argument("out_fwd_paired", help="paired R1 输出")
    pa.add_argument("out_fwd_unpaired", help="unpaired R1 输出（伴侣被滤除）")
    pa.add_argument("out_rev_paired", help="paired R2 输出")
    pa.add_argument("out_rev_unpaired", help="unpaired R2 输出")
    pa.add_argument("steps", nargs="*", help="修剪步骤字符串（可多个，按序透传）")
    _add_runtime_opts(pa)

    # se：单输入单输出
    ps = sub.add_parser("se", help=SUBCOMMANDS["se"])
    ps.add_argument("input", help="输入 FASTQ(.gz)")
    ps.add_argument("output", help="输出 FASTQ(.gz)")
    ps.add_argument("steps", nargs="*", help="修剪步骤字符串（可多个，按序透传）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项与常用透传选项。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（PE 默认 4 / SE 默认 2）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--java-mem-mb", type=int, dest="java_mem_mb",
                   help="JVM 最大堆内存 MB（默认取 optimization.default_mem_mb）")
    p.add_argument("--phred33", action="store_true", help="输入为 Phred+33 编码")
    p.add_argument("--phred64", action="store_true", help="输入为 Phred+64 编码")
    p.add_argument("--trimlog", help="修剪日志文件路径（可选）")
    p.add_argument("--summary", help="统计汇总输出文件（0.38+，可选）")
    p.add_argument("--dry-run", action="store_true", help="只构造并打印命令行，不执行")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:4s}  {v}")
        return 0
    if "--schema" in args:
        skill = TrimmomaticSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TrimmomaticSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    # --java-mem-mb 显式覆盖时重建 env_vars（JAVA_TOOL_OPTIONS -Xmx / TMPDIR）
    if getattr(ns, "java_mem_mb", None) and int(ns.java_mem_mb) != skill.mem_mb:
        skill.mem_mb = int(ns.java_mem_mb)
        skill.env_vars.update(skill._render_env_vars(
            skill.meta.get("optimization", {}).get("env_vars", {})
        ))

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "java_mem_mb", "dry_run")
          and v is not None}
    kw["threads"] = ns.threads

    if ns.dry_run:
        try:
            cmd = skill.build_command(ns.subcommand, dry_run=True, **kw)
        except (RuntimeError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        print(shlex.join(cmd))
        return 0

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
