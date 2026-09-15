#!/usr/bin/env python3
"""genomethreader native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align -genomic genome.fasta -protein proteins.fasta -species arabidopsis -o out.gff3
   python main.py consensus out_1.gff3 out_2.gff3 -species arabidopsis -o consensus.gff3
   python main.py getseq -getprotein out.gff3 -o proteins.fa
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（GenomeThreader 1.7.3）：
  align       gth -genomic <fa> [-cdna <fa>] [-protein <fa>] [-species S] [-intermediate] [-gff3out] -o <out>
  consensus   gthconsensus [-species S] [-gff3out] <intermediate...> -o <out>
  getseq      gthgetseq -getgenomic|-getprotein|-getcdna <intermediate...>   # FASTA 写 stdout
说明：gth 为单进程程序（无原生线程参数），--threads/--tmpdir 仅为技能接口统一保留；
      二进制按 GTH_HOME / ~/software/gth*/bin / PATH 惰性解析（测试时 monkeypatch）。
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
    "align": "gth -genomic <fa> [-cdna/-protein <fa>] [-species S] [-gff3out] -o <out>（相似性剪接比对/基因结构预测）",
    "consensus": "gthconsensus <intermediate...> [-species S] [-gff3out] -o <out>（合并中间结果为 consensus 剪接比对）",
    "getseq": "gthgetseq -getgenomic|-getprotein|-getcdna <intermediate...>（从中间结果提取 FASTA，写 stdout）",
}

# 子命令 -> 实际调用的上游二进制名
BINARIES = {
    "align": "gth",
    "consensus": "gthconsensus",
    "getseq": "gthgetseq",
}

# getseq 取序列类型 -> 上游旗标
GET_MODE_FLAGS = {
    "genomic": "-getgenomic",
    "protein": "-getprotein",
    "cdna": "-getcdna",
}
# 剪接位点模型可选物种（genomethreader 手册）
SPECIES = ("human", "mouse", "rat", "chicken", "drosophila", "nematode",
           "fission_yeast", "aspergillus", "arabidopsis", "maize", "rice", "medicago")


class GenomeThreaderSkill(base.SkillBase):
    software = "genomethreader"
    binary = "gth"

    def _resolve_tool(self, name: str) -> str:
        """惰性解析 GenomeThreader 二进制路径（GTH_HOME / ~/software/gth*/bin / PATH）。"""
        home = os.environ.get("GTH_HOME") or os.environ.get("GENOMETHREADER_HOME")
        if home:
            for cand in (Path(home) / "bin" / name, Path(home) / name):
                if cand.is_file():
                    return str(cand)
        for cand in sorted(Path.home().glob(f"software/gth*/bin/{name}")):
            if cand.is_file():
                return str(cand)
        found = base.which(name)
        if found:
            return found
        raise RuntimeError(
            f"未找到 GenomeThreader 二进制 '{name}'：请先通过 native/install.sh（或 Docker/Apptainer）安装，"
            f"或设置 GTH_HOME 指向 gth-<ver>-Linux_x86_64-64bit 安装目录。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（gth 单进程，仅记录）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 gth/gthconsensus/gthgetseq 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_tool(BINARIES[subcommand])
        cmd: list[str] = [binary]

        if subcommand == "align":
            genomic = kw.get("genomic") or kw.get("input")
            cdna = kw.get("cdna")
            protein = kw.get("protein")
            if not genomic:
                raise ValueError("align 缺少必填参数 genomic（基因组 FASTA）")
            if not (cdna or protein):
                raise ValueError("align 需至少提供 cdna 或 protein 之一")
            cmd += ["-genomic", str(genomic)]
            if cdna:
                cmd += ["-cdna", str(cdna)]
            if protein:
                cmd += ["-protein", str(protein)]
            if kw.get("species"):
                if kw["species"] not in SPECIES:
                    raise ValueError(f"species 非法: {kw['species']}（可选: {', '.join(SPECIES)}）")
                cmd += ["-species", str(kw["species"])]
            if kw.get("intermediate", True):
                cmd.append("-intermediate")
            if kw.get("gff3out", True):
                cmd.append("-gff3out")
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("force"):
                cmd.append("-force")

        elif subcommand == "consensus":
            inputs = kw.get("inputs") or kw.get("input")
            # argparse 收集为 list（可多个中间结果）；兼容单个字符串
            if isinstance(inputs, str):
                inputs = [inputs]
            if not inputs:
                raise ValueError("consensus 缺少必填参数 inputs（中间结果文件，可多个）")
            if kw.get("species"):
                cmd += ["-species", str(kw["species"])]
            if kw.get("gff3out", True):
                cmd.append("-gff3out")
            cmd += [str(f) for f in inputs]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        elif subcommand == "getseq":
            inputs = kw.get("inputs") or kw.get("input")
            if isinstance(inputs, str):
                inputs = [inputs]
            if not inputs:
                raise ValueError("getseq 缺少必填参数 inputs（中间结果文件）")
            mode = kw.get("get_mode") or kw.get("mode") or "protein"
            if mode not in GET_MODE_FLAGS:
                raise ValueError(f"get_mode 非法: {mode}（可选: {', '.join(GET_MODE_FLAGS)}）")
            cmd.append(GET_MODE_FLAGS[mode])
            cmd += [str(f) for f in inputs]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（gth 单进程，仅接口统一）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genomethreader-skill",
        description="genomethreader native 技能驱动（gth / gthconsensus / gthgetseq）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("-genomic", dest="genomic", help="基因组序列 FASTA")
    pa.add_argument("-cdna", dest="cdna", help="cDNA/EST 序列 FASTA")
    pa.add_argument("-protein", dest="protein", help="蛋白序列 FASTA")
    pa.add_argument("-species", dest="species", help="剪接位点模型物种")
    pa.add_argument("-o", "--output", help="输出 GFF3 路径")
    pa.add_argument("--no-intermediate", dest="intermediate", action="store_false",
                    help="关闭 -intermediate（不输出中间结果）")
    pa.add_argument("--no-gff3out", dest="gff3out", action="store_false", help="关闭 -gff3out")
    pa.add_argument("--force", action="store_true", help="强制覆盖输出文件")
    pa.add_argument("--extra-args", help="透传给 gth 的额外参数")
    _add_runtime_opts(pa)

    # consensus
    pc = sub.add_parser("consensus", help=SUBCOMMANDS["consensus"])
    pc.add_argument("inputs", nargs="+", help="中间结果文件（GFF3/XML，可多个）")
    pc.add_argument("-species", dest="species", help="剪接位点模型物种")
    pc.add_argument("-o", "--output", help="输出 consensus GFF3 路径")
    pc.add_argument("--no-gff3out", dest="gff3out", action="store_false", help="关闭 -gff3out")
    pc.add_argument("--extra-args", help="透传给 gthconsensus 的额外参数")
    _add_runtime_opts(pc)

    # getseq
    pg = sub.add_parser("getseq", help=SUBCOMMANDS["getseq"])
    pg.add_argument("inputs", nargs="+", help="中间结果文件")
    pg.add_argument("-get_mode", "--get-mode", dest="get_mode", choices=list(GET_MODE_FLAGS),
                    default="protein", help="取序列类型：genomic|protein|cdna（默认 protein）")
    pg.add_argument("-o", "--output", help="输出 FASTA 路径（默认写 stdout）")
    pg.add_argument("--extra-args", help="透传给 gthgetseq 的额外参数")
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
        skill = GenomeThreaderSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GenomeThreaderSkill()
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

    # getseq 的 stdout 落到 output 文件
    if ns.subcommand == "getseq" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
