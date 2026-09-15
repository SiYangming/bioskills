#!/usr/bin/env python3
"""genemarks native 标准入口驱动（原核基因预测：GeneMarkS-2 / GeneMarkS）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py gms2 -i genome.fasta --genome-type bacteria --gcode 11 --format gff \
       -o gms2.gff --fnn genes.fasta --faa proteins.fasta
   python main.py gms  genome.fasta --format GFF --fnn --faa --pdf
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（官方原核基因预测脚本）：
  gms2   gms2.pl --seq <fasta> --genome-type <archaea|bacteria|auto> [--gcode N] [--format F]
                 [--output <out>] [--fnn <fnn>] [--faa <faa>] [--ext <gff>] [--species <name>]
  gms    gmsn.pl --prok [--format GFF] [--fnn] [--faa] [--pdf] <fasta>
注意：运行前需已申请并放置密钥（gms2 -> ~/.gmhmmp2_key；旧版 -> ~/.gm_key）；
      GeneMarkS/GeneMarkS-2 未提供统一线程参数，--threads 仅为接口一致性保留（不注入命令行）。
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
from base import which  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "gms2": "GeneMarkS-2 原核基因预测（gms2.pl --seq --genome-type ...）",
    "gms": "旧版 GeneMarkS 原核基因预测（gmsn.pl --prok <fasta>）",
}

# 子命令 -> 官方脚本
SUBCOMMAND_BINARY = {"gms2": "gms2.pl", "gms": "gmsn.pl"}


class GeneMarkSSkill(base.SkillBase):
    software = "genemarks"
    binary = "gms2.pl"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析可执行脚本（测试可 monkeypatch 本方法）。"""
        name = name or self.binary
        path = which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行脚本 '{name}'，请先安装 GeneMarkS/GeneMarkS-2 并申请密钥（见 README）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 gms2.pl / gmsn.pl 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(SUBCOMMAND_BINARY[subcommand])
        input_file = kw.get("input") or kw.get("seq")
        if not input_file:
            raise ValueError(f"{subcommand} 缺少必填参数 input（输入基因组 FASTA）")

        cmd: list[str] = [binary]

        if subcommand == "gms2":
            cmd += ["--seq", str(input_file)]
            cmd += ["--genome-type", str(kw.get("genome_type") or "auto")]
            if kw.get("gcode") is not None:
                cmd += ["--gcode", str(kw["gcode"])]
            if kw.get("format"):
                cmd += ["--format", str(kw["format"])]
            if kw.get("output"):
                cmd += ["--output", str(kw["output"])]
            if kw.get("fnn"):
                cmd += ["--fnn", str(kw["fnn"])]
            if kw.get("faa"):
                cmd += ["--faa", str(kw["faa"])]
            if kw.get("ext"):
                cmd += ["--ext", str(kw["ext"])]
            if kw.get("species"):
                cmd += ["--species", str(kw["species"])]
        else:  # gms（旧版 GeneMarkS）
            cmd.append("--prok")
            if kw.get("format"):
                cmd += ["--format", str(kw["format"])]
            if kw.get("fnn"):
                cmd.append("--fnn")
            if kw.get("faa"):
                cmd.append("--faa")
            if kw.get("pdf"):
                cmd.append("--pdf")
            if kw.get("output"):
                cmd += ["--output", str(kw["output"])]
            cmd.append(str(input_file))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 注：无统一线程参数，--threads 不注入命令行
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
    p.add_argument("--threads", type=int, help="线程数（接口兼容；无统一线程参数，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genemarks-skill",
        description="genemarks native 技能驱动（原核基因预测：GeneMarkS-2 / GeneMarkS）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # gms2
    p2 = sub.add_parser("gms2", help=SUBCOMMANDS["gms2"])
    p2.add_argument("-i", "--input", required=True, help="输入基因组 FASTA（--seq）")
    p2.add_argument("--genome-type", dest="genome_type", help="archaea|bacteria|auto（默认 auto）")
    p2.add_argument("--gcode", type=int, help="遗传密码子表（11/4/25/15）")
    p2.add_argument("--format", help="输出格式：lst|gff|gtf|gff3")
    p2.add_argument("-o", "--output", help="输出坐标文件（默认 gms2.lst）")
    p2.add_argument("--fnn", help="输出基因核酸序列文件（FASTA）")
    p2.add_argument("--faa", help="输出蛋白序列文件（FASTA）")
    p2.add_argument("--ext", help="外部证据文件（GFF，PLUS 模式）")
    p2.add_argument("--species", help="模型文件中的物种名")
    p2.add_argument("--extra-args", help="透传给 gms2.pl 的额外参数")
    _add_runtime_opts(p2)

    # gms（旧版）
    pg = sub.add_parser("gms", help=SUBCOMMANDS["gms"])
    pg.add_argument("input", nargs="?", help="输入基因组 FASTA（位置参数）")
    pg.add_argument("-i", "--input-opt", dest="input_opt", help="输入基因组 FASTA（别名）")
    pg.add_argument("--format", help="输出格式：LST|GFF")
    pg.add_argument("--fnn", action="store_true", help="输出基因核酸序列")
    pg.add_argument("--faa", action="store_true", help="输出蛋白序列")
    pg.add_argument("--pdf", action="store_true", help="输出可视化 PDF")
    pg.add_argument("-o", "--output", help="输出坐标文件（可选）")
    pg.add_argument("--extra-args", help="透传给 gmsn.pl 的额外参数")
    _add_runtime_opts(pg)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:6s} {v}")
        return 0
    if "--schema" in args:
        skill = GeneMarkSSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GeneMarkSSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "input_opt") and v is not None}
    # gms 的 --input-opt 作为 input 别名
    if getattr(ns, "input_opt", None):
        kw.setdefault("input", ns.input_opt)
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
