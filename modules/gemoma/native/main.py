#!/usr/bin/env python3
"""gemoma native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py extractor -a ref.gff -g ref.fasta -p ref_proteins.fasta -c ref_cds.fasta
   python main.py pipeline -t target.fasta -a ref.gff -g ref.fasta -p ref_proteins.fasta \
       -c ref_cds.fasta -o gemoma_output --threads 8
   python main.py gaf -g gemoma_output/predicted_annotation.gff -o gemoma.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（GeMoMa 1.9，Java CLI）：
  extractor           java -jar GeMoMa-<ver>.jar CLI Extractor -a <gff> -g <ref> -p <prot> -c <cds>
  pipeline            java -jar GeMoMa-<ver>.jar CLI GeMoMaPipeline -t <target> -a .. -g .. -p .. -c .. -o <dir> --threads N
  gaf                 java -jar GeMoMa-<ver>.jar CLI GAF -g <predicted.gff> -o <out.gff3>
  annotation_evidence java -jar GeMoMa-<ver>.jar CLI AnnotationEvidence <extra-args>
  coding_quarry       java -jar GeMoMa-<ver>.jar CLI CodingQuarry <extra-args>
jar 按 GEMOMA_JAR / GEMOMA_HOME / ~/software/GeMoMa*/ / conda share 惰性解析（测试时 monkeypatch）；
JAVA_OPTS（-Xmx）经 optimization.env_vars 透传给 java 进程。
"""
from __future__ import annotations

import argparse
import json
import os
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
    "extractor": "Extractor：从参考基因组 + 注释中提取 CDS 与蛋白序列（-a/-g/-p/-c）",
    "pipeline": "GeMoMaPipeline：完整同源基因预测流程（-t 目标基因组，-a/-g/-p/-c 参考，-o 输出目录，--threads）",
    "gaf": "GAF：对预测注释进行过滤/处理（-g 输入 GFF，-o 输出 GFF3）",
    "annotation_evidence": "AnnotationEvidence：注释证据整合（参数经 --extra-args 透传）",
    "coding_quarry": "CodingQuarry：真菌基因预测专用模块（参数经 --extra-args 透传）",
}

# 子命令 -> GeMoMa CLI 模块名
MODULES = {
    "extractor": "Extractor",
    "pipeline": "GeMoMaPipeline",
    "gaf": "GAF",
    "annotation_evidence": "AnnotationEvidence",
    "coding_quarry": "CodingQuarry",
}


class GeMoMaSkill(base.SkillBase):
    software = "gemoma"
    binary = "GeMoMa"

    def _java(self) -> str:
        """返回 java 可执行文件（优先 $JAVA_HOME/bin/java）。"""
        java_home = os.environ.get("JAVA_HOME")
        if java_home:
            cand = Path(java_home) / "bin" / "java"
            if cand.is_file():
                return str(cand)
        return "java"

    def _resolve_jar(self) -> str:
        """惰性解析 GeMoMa jar 路径（GEMOMA_JAR / GEMOMA_HOME / ~/software / conda share）。"""
        explicit = os.environ.get("GEMOMA_JAR")
        if explicit and Path(explicit).is_file():
            return str(explicit)
        home = os.environ.get("GEMOMA_HOME")
        if home:
            for cand in sorted(Path(home).glob("GeMoMa-*.jar")):
                return str(cand)
        for cand in sorted(Path.home().glob("software/GeMoMa*/GeMoMa-*.jar")):
            return str(cand)
        wrapper = base.which("GeMoMa")
        if wrapper:
            p = Path(wrapper).resolve()
            for pattern in (f"../share/GeMoMa*/GeMoMa-*.jar", f"../share/gemoma*/GeMoMa-*.jar",
                            "GeMoMa-*.jar", "../*GeMoMa-*.jar"):
                for cand in sorted(p.parent.glob(pattern)):
                    if cand.is_file():
                        return str(cand)
        raise RuntimeError(
            "未找到 GeMoMa jar：请先通过 native/install.sh（或 Docker/Apptainer）安装，"
            "或设置 GEMOMA_JAR / GEMOMA_HOME 指向 GeMoMa-<ver>.jar 所在目录。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 `java -jar GeMoMa-<ver>.jar CLI <Module> ...` 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = [self._java(), "-jar", self._resolve_jar(), "CLI", MODULES[subcommand]]

        if subcommand == "extractor":
            if not kw.get("annotation"):
                raise ValueError("extractor 缺少必填参数 annotation（参考注释 GFF）")
            if not kw.get("genome"):
                raise ValueError("extractor 缺少必填参数 genome（参考基因组 FASTA）")
            cmd += ["-a", str(kw["annotation"]), "-g", str(kw["genome"])]
            if kw.get("proteins"):
                cmd += ["-p", str(kw["proteins"])]
            if kw.get("cds"):
                cmd += ["-c", str(kw["cds"])]

        elif subcommand == "pipeline":
            if not kw.get("target"):
                raise ValueError("pipeline 缺少必填参数 target（目标基因组 FASTA）")
            cmd += ["-t", str(kw["target"])]
            for flag, key in (("-a", "annotation"), ("-g", "genome"),
                              ("-p", "proteins"), ("-c", "cds")):
                if kw.get(key):
                    cmd += [flag, str(kw[key])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            cmd += ["--threads", str(self._effective_threads(subcommand, kw.get("threads")))]

        elif subcommand == "gaf":
            gff = kw.get("input") or kw.get("annotation")
            if not gff:
                raise ValueError("gaf 缺少必填参数 input（预测注释 GFF）")
            cmd += ["-g", str(gff)]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        else:  # annotation_evidence / coding_quarry：官方 key=value 参数经 --extra-args 透传
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        # 高级透传（官方 CLI 使用 key=value 语法，如 "GeMoMa.Score=ReAlign"）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gemoma-skill",
        description="gemoma native 技能驱动（java -jar GeMoMa CLI 模块；自动注入线程/JAVA_OPTS）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # extractor
    pe = sub.add_parser("extractor", help=SUBCOMMANDS["extractor"])
    pe.add_argument("-a", "--annotation", help="参考注释 GFF")
    pe.add_argument("-g", "--genome", help="参考基因组 FASTA")
    pe.add_argument("-p", "--proteins", help="参考蛋白序列 FASTA（输出）")
    pe.add_argument("-c", "--cds", help="参考 CDS 序列 FASTA（输出）")
    pe.add_argument("--extra-args", help="透传给 Extractor 的额外参数")
    _add_runtime_opts(pe)

    # pipeline
    pp = sub.add_parser("pipeline", help=SUBCOMMANDS["pipeline"])
    pp.add_argument("-t", "--target", help="目标基因组 FASTA")
    pp.add_argument("-a", "--annotation", help="参考注释 GFF")
    pp.add_argument("-g", "--genome", help="参考基因组 FASTA")
    pp.add_argument("-p", "--proteins", help="参考蛋白序列 FASTA")
    pp.add_argument("-c", "--cds", help="参考 CDS 序列 FASTA")
    pp.add_argument("-o", "--output", help="输出目录")
    pp.add_argument("--extra-args", help="透传给 GeMoMaPipeline 的额外参数（官方 key=value）")
    _add_runtime_opts(pp)

    # gaf
    pg = sub.add_parser("gaf", help=SUBCOMMANDS["gaf"])
    pg.add_argument("input", nargs="?", help="预测注释 GFF（别名 --input）")
    pg.add_argument("--input", help="预测注释 GFF 的别名")
    pg.add_argument("-g", "--annotation", help="预测注释 GFF（与 input 等价）")
    pg.add_argument("-o", "--output", help="输出 GFF3 路径")
    pg.add_argument("--extra-args", help="透传给 GAF 的额外参数")
    _add_runtime_opts(pg)

    # annotation_evidence
    pv = sub.add_parser("annotation_evidence", help=SUBCOMMANDS["annotation_evidence"])
    pv.add_argument("-o", "--output", help="输出文件")
    pv.add_argument("--extra-args", help="透传给 AnnotationEvidence 的参数（官方 key=value）")
    _add_runtime_opts(pv)

    # coding_quarry
    pc = sub.add_parser("coding_quarry", help=SUBCOMMANDS["coding_quarry"])
    pc.add_argument("-o", "--output", help="输出文件")
    pc.add_argument("--extra-args", help="透传给 CodingQuarry 的参数（官方 key=value）")
    _add_runtime_opts(pc)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:20s} {v}")
        return 0
    if "--schema" in args:
        skill = GeMoMaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GeMoMaSkill()
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

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
