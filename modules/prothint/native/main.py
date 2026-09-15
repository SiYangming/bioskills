#!/usr/bin/env python3
"""prothint native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict genome.fasta proteins.fasta --workdir prothint_out --threads 8
   python main.py high_confidence prothint_out/prothint.gff -o evidence.gff
   python main.py augustus_hints prothint_out/prothint.gff prothint_out/evidence.gff \
       prothint_out/chains.gff hints.gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（ProtHint v2.4.0，均为 Python 3 脚本）：
  predict           python3 prothint.py <genome.fasta> <proteins.fasta> [--workdir W] [--threads N] ...
  high_confidence   python3 print_high_confidence.py <prothint.gff>            # 输出到 stdout
  augustus_hints    python3 prothint2augustus.py <prothint.gff> <evidence.gff> <chains.gff> <output.gff>
脚本按 PROTHINT_HOME / ~/software/ProtHint-*/bin / PATH 惰性解析（测试时 monkeypatch）。
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
    "predict": "genome.fasta + proteins.fasta -> prothint.gff/evidence.gff/prothint_augustus.gff（prothint.py 主流程）",
    "high_confidence": "prothint.gff -> evidence.gff（print_high_confidence.py 高置信 hints 筛选，写 stdout）",
    "augustus_hints": "prothint.gff + evidence.gff + chains.gff -> AUGUSTUS/BRAKER hints GFF（prothint2augustus.py）",
}

# 子命令 -> 实际调用的上游脚本名
SCRIPTS = {
    "predict": "prothint.py",
    "high_confidence": "print_high_confidence.py",
    "augustus_hints": "prothint2augustus.py",
}


class ProthintSkill(base.SkillBase):
    software = "prothint"
    binary = "prothint.py"

    def _resolve_script(self, name: str) -> str:
        """惰性解析 ProtHint 上游脚本路径（PROTHINT_HOME / ~/software/ProtHint-*/bin / PATH）。"""
        home = os.environ.get("PROTHINT_HOME") or os.environ.get("PROTHINT_DIR")
        if home:
            for cand in (Path(home) / "bin" / name, Path(home) / name):
                if cand.is_file():
                    return str(cand)
        for cand in sorted(Path.home().glob(f"software/ProtHint*/bin/{name}")):
            if cand.is_file():
                return str(cand)
        found = base.which(name)
        if found:
            return found
        raise RuntimeError(
            f"未找到 ProtHint 脚本 '{name}'：请先通过 native/install.sh（或 Docker/Apptainer）安装，"
            f"或设置 PROTHINT_HOME 指向 ProtHint 安装目录。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建上游脚本命令行（统一 python3 <script> 驱动）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        script = self._resolve_script(SCRIPTS[subcommand])
        cmd: list[str] = [sys.executable, script]

        if subcommand == "predict":
            genome = kw.get("genome") or kw.get("input")
            proteins = kw.get("proteins")
            if not genome:
                raise ValueError("predict 缺少必填参数 genome（目标基因组 FASTA）")
            if not proteins:
                raise ValueError("predict 缺少必填参数 proteins（参考蛋白 FASTA）")
            cmd += [str(genome), str(proteins)]
            if kw.get("workdir"):
                cmd += ["--workdir", str(kw["workdir"])]
            if kw.get("gene_mark_gtf"):
                cmd += ["--geneMarkGtf", str(kw["gene_mark_gtf"])]
            if kw.get("diamond_pairs"):
                cmd += ["--diamondPairs", str(kw["diamond_pairs"])]
            if kw.get("fungus"):
                cmd.append("--fungus")
            if kw.get("evalue") is not None:
                cmd += ["--evalue", str(kw["evalue"])]
            cmd += ["--threads", str(self._effective_threads(subcommand, kw.get("threads")))]

        elif subcommand == "high_confidence":
            gff = kw.get("prothint_gff") or kw.get("input")
            if not gff:
                raise ValueError("high_confidence 缺少必填参数 prothint_gff（prothint.gff）")
            cmd.append(str(gff))
            if kw.get("intron_coverage") is not None:
                cmd += ["--intronCoverage", str(kw["intron_coverage"])]
            if kw.get("start_coverage") is not None:
                cmd += ["--startCoverage", str(kw["start_coverage"])]
            if kw.get("stop_coverage") is not None:
                cmd += ["--stopCoverage", str(kw["stop_coverage"])]
            if kw.get("add_top_proteins"):
                cmd.append("--addTopProteins")
            if kw.get("add_full_aligned"):
                cmd.append("--addFullAligned")

        elif subcommand == "augustus_hints":
            prothint_gff = kw.get("prothint_gff") or kw.get("input")
            evidence = kw.get("evidence_gff")
            chains = kw.get("chains_gff")
            output = kw.get("output")
            missing = [n for n, v in (("prothint_gff", prothint_gff), ("evidence_gff", evidence),
                                      ("chains_gff", chains), ("output", output)) if not v]
            if missing:
                raise ValueError(f"augustus_hints 缺少必填参数: {', '.join(missing)}")
            cmd += [str(prothint_gff), str(evidence), str(chains), str(output)]

        # 高级透传（慎用）
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
        prog="prothint-skill",
        description="prothint native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("genome", help="目标基因组 multi-FASTA")
    pp.add_argument("proteins", help="参考蛋白 multi-FASTA")
    pp.add_argument("--workdir", help="结果与临时文件目录（默认当前目录）")
    pp.add_argument("--gene-mark-gtf", dest="gene_mark_gtf", help="GeneMark-ES 预测 GTF")
    pp.add_argument("--diamond-pairs", dest="diamond_pairs", help="DIAMOND 命中文件")
    pp.add_argument("--fungus", action="store_true", help="真菌模式")
    pp.add_argument("--evalue", type=float, help="DIAMOND E-value 阈值（默认 0.001）")
    pp.add_argument("--extra-args", help="透传给 prothint.py 的额外参数")
    _add_runtime_opts(pp)

    # high_confidence
    ph = sub.add_parser("high_confidence", help=SUBCOMMANDS["high_confidence"])
    ph.add_argument("prothint_gff", nargs="?", help="prothint.gff（别名 --input）")
    ph.add_argument("--input", help="prothint.gff 的别名")
    ph.add_argument("-o", "--output", help="输出 evidence.gff 路径（默认写 stdout）")
    ph.add_argument("--intron-coverage", dest="intron_coverage", type=int, help="intron 覆盖阈值")
    ph.add_argument("--start-coverage", dest="start_coverage", type=int, help="start 覆盖阈值")
    ph.add_argument("--stop-coverage", dest="stop_coverage", type=int, help="stop 覆盖阈值")
    ph.add_argument("--add-top-proteins", dest="add_top_proteins", action="store_true",
                    help="额外保留 top 蛋白相关 hints")
    ph.add_argument("--add-full-aligned", dest="add_full_aligned", action="store_true",
                    help="额外保留全蛋白比对相关 hints")
    _add_runtime_opts(ph)

    # augustus_hints
    pa = sub.add_parser("augustus_hints", help=SUBCOMMANDS["augustus_hints"])
    pa.add_argument("prothint_gff", help="prothint.gff")
    pa.add_argument("evidence_gff", help="evidence.gff")
    pa.add_argument("chains_gff", help="chains.gff")
    pa.add_argument("output", help="输出 AUGUSTUS/BRAKER hints GFF")
    _add_runtime_opts(pa)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = ProthintSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ProthintSkill()
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

    # high_confidence 的 stdout 落到 output 文件（print_high_confidence.py 写 stdout）
    if ns.subcommand == "high_confidence" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
