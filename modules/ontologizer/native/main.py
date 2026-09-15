#!/usr/bin/env python3
"""ontologizer native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py enrich -g go.obo -a gene_association.gaf2 -s S1_vs_S3_S1_UP.list \
       -p population.list -c Parent-Child-Union -m Bonferroni -o ./enrichment
   python main.py gui
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  enrich  java <JAVA_OPTS> -jar Ontologizer.jar -g <go.obo> -a <assoc> -s <study> -p <pop> ...
  gui     java <JAVA_OPTS> -jar OntologizerGui.jar
JVM 堆内存与临时目录经 JAVA_OPTS（optimization.env_vars，含 {tmpdir} 占位）透传；Ontologizer 单进程，
--threads 仅作统一接口与上层调度参考，不注入命令行。
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
    "enrich": "GO 富集分析：java -jar Ontologizer.jar -g <go.obo> -a <assoc> -s <study> -p <pop> ...",
    "gui": "图形界面：java -jar OntologizerGui.jar（需 X11/显示环境）",
}

# 子命令 -> jar 文件名
JAR_BY_SUBCOMMAND = {
    "enrich": "Ontologizer.jar",
    "gui": "OntologizerGui.jar",
}

CALCULATION_CHOICES = (
    "MGSA", "Parent-Child-Intersection", "Parent-Child-Union",
    "Term-For-Term", "Topology-Elim", "Topology-Weighted",
)

MTC_CHOICES = (
    "Benjamini-Hochberg", "Benjamini-Yekutieli", "Bonferroni",
    "Bonferroni-Holm", "None", "Westfall-Young-Single-Step",
    "Westfall-Young-Step-Down",
)


class OntologizerSkill(base.SkillBase):
    software = "ontologizer"
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

    def _resolve_jar(self, subcommand: str) -> str:
        """解析 Ontologizer jar：优先 $ONTOLOGIZER_JAR / $ONTOLOGIZER_HOME，其次常见安装位置。"""
        jar_name = JAR_BY_SUBCOMMAND[subcommand]
        cands: list[Path] = []
        explicit = os.environ.get("ONTOLOGIZER_JAR")
        if explicit:
            cands.append(Path(explicit))
        home = os.environ.get("ONTOLOGIZER_HOME")
        if home:
            cands += [Path(home) / jar_name, Path(home) / "bin" / jar_name]
        cands += [
            Path.home() / "software" / "ontologizer" / jar_name,
            Path.home() / "software" / "ontologizer-2.1" / jar_name,
            Path("/opt/ontologizer") / jar_name,
        ]
        for cand in cands:
            if cand.is_file():
                return str(cand)
        raise RuntimeError(
            f"未找到 {jar_name}；请将其放入 PATH/安装目录或设置 ONTOLOGIZER_JAR（enrich 用 "
            f"Ontologizer.jar）/ ONTOLOGIZER_HOME。官方下载：http://ontologizer.de/cmdline/"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 java -jar Ontologizer 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = self._java_prefix()
        cmd.append(self._resolve_jar(subcommand))

        if subcommand == "gui":
            self._effective_threads(subcommand, kw.get("threads"))
            return cmd

        # enrich
        go = kw.get("go")
        assoc = kw.get("association")
        study = kw.get("studyset") or kw.get("study")
        pop = kw.get("population")
        missing = [n for n, v in (("go", go), ("association", assoc),
                                  ("studyset", study), ("population", pop)) if not v]
        if missing:
            raise ValueError(f"enrich 缺少必填参数: {', '.join(missing)}（-g/-a/-s/-p）")

        cmd += ["-g", str(go), "-a", str(assoc), "-s", str(study), "-p", str(pop)]

        calc = kw.get("calculation")
        if calc:
            if calc not in CALCULATION_CHOICES:
                raise ValueError(f"-c 计算方法非法（可选: {', '.join(CALCULATION_CHOICES)}）")
            cmd += ["-c", calc]
        mtc = kw.get("mtc")
        if mtc:
            if mtc not in MTC_CHOICES:
                raise ValueError(f"-m MTC 非法（可选: {', '.join(MTC_CHOICES)}）")
            cmd += ["-m", mtc]
        if kw.get("outdir"):
            cmd += ["-o", str(kw["outdir"])]
        if kw.get("resample_steps") is not None:
            cmd += ["-r", str(kw["resample_steps"])]
        if kw.get("size_tolerance") is not None:
            cmd += ["-t", str(kw["size_tolerance"])]
        if kw.get("filter_file"):
            cmd += ["-f", str(kw["filter_file"])]
        if kw.get("dot"):
            cmd += ["-d"]
        if kw.get("annotate"):
            cmd += ["-n"]
        if kw.get("ignore_unassociated"):
            cmd += ["-i"]

        # 线程：Ontologizer 单进程，仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（Ontologizer 单进程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 JAVA_OPTS -Djava.io.tmpdir）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ontologizer-skill",
        description="ontologizer native 技能驱动（GO 富集分析；JVM 堆内存经 JAVA_OPTS 注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pe = sub.add_parser("enrich", help=SUBCOMMANDS["enrich"])
    pe.add_argument("-g", "--go", help="GO 本体文件 go.obo")
    pe.add_argument("-a", "--association", help="基因-GO 关联文件 gene_association.gaf")
    pe.add_argument("-s", "--studyset", help="study set 文件或目录")
    pe.add_argument("-p", "--population", help="population 背景基因文件")
    pe.add_argument("-o", "--outdir", help="结果输出目录")
    pe.add_argument("-c", "--calculation", help="计算方法（默认 Parent-Child-Union）")
    pe.add_argument("-m", "--mtc", help="多重检验校正（默认 None）")
    pe.add_argument("-r", "--resample-steps", dest="resample_steps", type=int, help="重采样步数")
    pe.add_argument("-t", "--size-tolerance", dest="size_tolerance", help="重采样尺寸偏差百分比")
    pe.add_argument("-f", "--filter-file", dest="filter_file", help="基因名过滤规则文件")
    pe.add_argument("-d", "--dot", action="store_true", help="额外输出 GraphViz .dot 图")
    pe.add_argument("-n", "--annotate", action="store_true", help="额外输出 study set 注释文件")
    pe.add_argument("-i", "--ignore", dest="ignore_unassociated", action="store_true",
                    help="忽略无任何 GO 关联的基因")
    pe.add_argument("--extra-args", help="透传给 Ontologizer 的额外参数")
    _add_runtime_opts(pe)

    pg = sub.add_parser("gui", help=SUBCOMMANDS["gui"])
    _add_runtime_opts(pg)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = OntologizerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OntologizerSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars = skill._render_env_vars(
            (skill.meta.get("optimization", {}) or {}).get("env_vars", {})
        )

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
