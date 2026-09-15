#!/usr/bin/env python3
"""pilon native 标准入口驱动（Java / jar 工具）。

Pilon 是 Java 程序，官方发布物为单个 pilon-<ver>.jar，CLI 形如：
    java -jar pilon-1.23.jar --genome genome.fa --frags aln.sorted.bam \
        --fix all --changes --output pilon01
    java -jar pilon-1.23.jar --genome genome.fa --frags aln.bam --variant --vcf
bioconda / brew 另提供 `pilon` launcher（内部仍调 java -jar）。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py correct --genome genome.fa --frags aln.sorted.bam --fix all --changes --output pilon01
   python main.py correct --genome genome.fa --frags aln.bam --variant --vcf --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema | --list-commands

自动优化（JVM 类工具）：
- launcher 解析：PILON_JAR 环境变量 → conda/官方 jar 常见位置（glob）→ PATH 中 `pilon` 封装；
  走 `java -jar` 时以 JAVA_OPTS（-Xmx / -Djava.io.tmpdir，见 meta optimization.env_vars）注入堆内存与临时目录。
- --threads 透传 pilon 的 --threads（线程优先级：用户显式 > per_subcommand_threads > default_cpus）。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "correct": "组装修正 / 变异检测（--genome + 一个或多个 --frags/--jumps/--unpaired/--bam；"
               "--fix all --changes 修正，或 --variant [--vcf] 做变异检测）",
}

# pilon jar 候选位置（{conda} 渲染为 CONDA_PREFIX；支持 ** 递归）
_JAR_GLOBS = [
    "{conda}/share/**/pilon*.jar",
    "{conda}/opt/pilon/pilon*.jar",
    "{conda}/share/pilon*/pilon*.jar",
    "{conda}/bin/pilon*.jar",
    "~/software/pilon*/pilon*.jar",
    "/opt/pilon/pilon*.jar",
    "./pilon*.jar",
]


class PilonSkill(base.SkillBase):
    software = "pilon"
    binary = "java"   # JVM 运行时；pilon 本体为 jar

    def _jar_candidates(self) -> list[str]:
        cands: list[str] = []
        env_jar = os.environ.get("PILON_JAR")
        if env_jar:
            cands.append(env_jar)
        conda = os.environ.get("CONDA_PREFIX", "")
        for pat in _JAR_GLOBS:
            p = pat.format(conda=conda)
            if p.startswith("~"):
                p = str(Path(p).expanduser())
            cands.append(p)
        return cands

    def _resolve_jar(self) -> str:
        """惰性定位 pilon jar（可用 monkeypatch 覆盖，测试不依赖工具已安装）。"""
        for c in self._jar_candidates():
            hits = sorted(glob.glob(c, recursive=True))
            if hits:
                return hits[0]
        raise RuntimeError(
            "未找到 pilon jar；请安装（conda/mamba：bioconda::pilon=1.23；或 brew pilon），"
            "或从官方 release 下载 pilon-1.23.jar 并 export PILON_JAR=/path/to/pilon-1.23.jar"
        )

    def _resolve_launcher(self) -> list[str]:
        """返回命令前缀：['java','-jar',jar]（首选）或 PATH 中的 ['pilon'] 兜底。"""
        try:
            jar = self._resolve_jar()
        except RuntimeError:
            wrapper = base.which("pilon")
            if wrapper:
                return [wrapper]
            raise
        java = self._resolve_binary()
        return [java, "-jar", jar]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        genome = kw.get("genome")
        if not genome:
            raise ValueError("correct 缺少必填参数 genome（--genome <组装 FASTA>）")

        launcher = self._resolve_launcher()
        cmd: list[str] = list(launcher)
        cmd += ["--genome", str(genome)]

        # 读对/比对输入（可按类型多给）
        for key, flag in (("frags", "--frags"), ("jumps", "--jumps"),
                          ("unpaired", "--unpaired"), ("bam", "--bam"),
                          ("tracks", "--tracks")):
            val = kw.get(key)
            if val:
                cmd += [flag, str(val)]

        fix = kw.get("fix")
        if fix:
            cmd += ["--fix", str(fix)]
        if kw.get("changes"):
            cmd += ["--changes"]
        if kw.get("variant"):
            cmd += ["--variant"]
        if kw.get("vcf"):
            cmd += ["--vcf"]

        outdir = kw.get("outdir")
        if outdir:
            cmd += ["--outdir", str(outdir)]
        output = kw.get("output")
        if output:
            cmd += ["--output", str(output)]

        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["--threads", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖线程数（透传 pilon --threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（JAVA_OPTS -Djava.io.tmpdir）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="pilon-skill",
        description="pilon native 技能驱动（java -jar；JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("correct", help=SUBCOMMANDS["correct"])
    pc.add_argument("--genome", required=True, help="待修正的参考组装 FASTA")
    pc.add_argument("--frags", help="双端（paired-end）比对 BAM")
    pc.add_argument("--jumps", help="大片段（mate-pair）比对 BAM")
    pc.add_argument("--unpaired", help="未配对 reads 比对 BAM")
    pc.add_argument("--bam", help="通用比对 BAM（不区分读对类型）")
    pc.add_argument("--tracks", help="轨迹文件（tracks.txt）")
    pc.add_argument("--fix", default="all",
                    help="修正类型列表（all|snps|indels|local|bases|gaps；默认 all）")
    pc.add_argument("--changes", dest="changes", action="store_true", default=True,
                    help="输出变化清单（默认开启）")
    pc.add_argument("--no-changes", dest="changes", action="store_false",
                    help="不输出变化清单")
    pc.add_argument("-o", "--output", help="输出文件前缀（<output>.fasta / <output>.changes）")
    pc.add_argument("--outdir", help="输出目录")
    pc.add_argument("--variant", action="store_true", help="变异检测模式（而非组装修正）")
    pc.add_argument("--vcf", action="store_true", help="变异输出为 VCF（配合 --variant）")
    pc.add_argument("--extra-args", dest="extra_args", help="透传给 pilon 的额外参数")
    _add_runtime_opts(pc)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = PilonSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PilonSkill()
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
