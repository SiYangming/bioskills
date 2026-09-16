#!/usr/bin/env python3
"""fgenesh native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict genome.fasta -L params/fungi.par -o fgenesh.gff -gff --threads 8
   python main.py predict genome.fasta --species fungi --params-dir /opt/fgenesh/params -o out -gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  predict  fgenesh <genome.fa> -L <params.par> -o <output_prefix> [-gff] [-exon] [-gene] -cpu <N>
⚠️ FGENESH 为 Softberry 许可受限软件：使用前须获得学术/商业许可并解压发行包加入 PATH。
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
    "predict": "从头基因预测（fgenesh <genome.fa> -L <params.par> -o <prefix> -gff -cpu N）",
}

# 支持的物种预设（对应 Softberry 参数文件 <species>.par）
SPECIES_PRESETS = (
    "fungi", "arabidopsis", "rice", "human", "mouse", "drosophila", "worm",
)


class FgeneshSkill(base.SkillBase):
    software = "fgenesh"
    binary = "fgenesh"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 fgenesh 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        genome = kw.get("genome")
        if not genome:
            raise ValueError("predict 缺少必填位置参数 genome（待预测基因组 FASTA）")
        cmd: list[str] = [binary, str(genome)]

        # 参数文件：--params 直接指定，或 --species + --params-dir 解析
        params = kw.get("params")
        if not params and kw.get("species"):
            species = str(kw["species"])
            if species not in SPECIES_PRESETS:
                raise ValueError(
                    f"未知物种预设: {species}（可选：{'|'.join(SPECIES_PRESETS)}）"
                )
            params_dir = kw.get("params_dir")
            if not params_dir:
                raise ValueError("使用 --species 时必须提供 --params-dir（参数文件目录）")
            params = str(Path(params_dir) / f"{species}.par")
        if not params:
            raise ValueError("predict 缺少参数文件：请用 -L/--params 指定 .par，或用 --species + --params-dir")
        cmd += ["-L", str(params)]

        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        if kw.get("gff"):
            cmd.append("-gff")
        if kw.get("exon_only"):
            cmd.append("-exon")
        if kw.get("gene_only"):
            cmd.append("-gene")

        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-cpu", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fgenesh-skill",
        description="FGENESH native 技能驱动（Softberry 从头基因预测；许可受限）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("genome", help="待预测基因组序列 FASTA")
    pp.add_argument("-L", "--params", help="物种参数文件（如 fungi.par）")
    pp.add_argument("--species", choices=SPECIES_PRESETS, help="物种预设（自动解析为 <params-dir>/<species>.par）")
    pp.add_argument("--params-dir", dest="params_dir", help="参数文件目录（配合 --species）")
    pp.add_argument("-o", "--output", help="输出文件前缀")
    pp.add_argument("-gff", dest="gff", action="store_true", help="以 GFF 格式输出")
    pp.add_argument("-exon", dest="exon_only", action="store_true", help="仅输出外显子")
    pp.add_argument("-gene", dest="gene_only", action="store_true", help="仅输出基因")
    pp.add_argument("--extra-args", help="透传给 fgenesh 的额外参数")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -cpu N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = FgeneshSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FgeneshSkill()
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
