#!/usr/bin/env python3
"""sepp native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -t ref.tree -a ref_aln.fasta -f fragments.fasta -r ref.RAxML_info \
       -o placements -d /abs/out --threads 8
   python main.py upp -s seqs.fasta -o upp_out --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（SEPP 4.3.10，bash 名不变，见官方 sepp/ensemble.py + sepp/config.py）：
  run   run_sepp.py -t <tree> -a <aln> -f <frag> [-r <raxml_info>] [-A N] [-P N] [-F N]
                    [-c <cfg>] [-o <prefix>] [-d <outdir>] [-x <cpu>] [-p <tmpdir>]
  upp   run_upp.py  -s <seqs> [-t <tree>] [-a <aln>] [-A N] [-c <cfg>]
                    [-o <prefix>] [-d <outdir>] [-x <cpu>] [-p <tmpdir>]
所有子命令自动注入线程（-x/--cpu）与临时目录（-p）。
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
    "run": "SEPP 系统发育放置：tree+alignment+fragments(+RAxML_info) -> placement.json/alignment.fasta",
    "upp": "UPP 超大规模比对：未比对序列(+backbone tree/alignment) -> 扩展比对",
}

# 子命令 -> 实际可执行脚本（同包提供的两个 console script）
SUBCOMMAND_BINARY = {
    "run": "run_sepp.py",
    "upp": "run_upp.py",
}


class SeppSkill(base.SkillBase):
    software = "sepp"
    binary = "run_sepp.py"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析可执行文件（测试可 monkeypatch 本方法）。"""
        name = name or self.binary
        path = which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先通过 Conda/Docker/Apptainer 安装 sepp。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 run_sepp.py / run_upp.py 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(SUBCOMMAND_BINARY[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))
        # 临时目录：优先用户 --tmpdir，回退实例 tmpdir
        tmpdir = kw.get("tmpdir") or self.tmpdir

        cmd: list[str] = [binary]

        if subcommand == "run":
            tree = kw.get("tree")
            alignment = kw.get("alignment")
            fragment = kw.get("fragment") or kw.get("input")
            if not (tree and alignment and fragment):
                raise ValueError("run 缺少必填参数：tree(-t) / alignment(-a) / fragment(-f)")
            cmd += ["-t", str(tree), "-a", str(alignment), "-f", str(fragment)]
            raxml = kw.get("raxml_info")
            if raxml:
                cmd += ["-r", str(raxml)]
        else:  # upp
            seqs = kw.get("sequence_file") or kw.get("input")
            if not seqs:
                raise ValueError("upp 缺少必填参数 sequence_file(-s)")
            cmd += ["-s", str(seqs)]
            if kw.get("tree"):
                cmd += ["-t", str(kw["tree"])]
            if kw.get("alignment"):
                cmd += ["-a", str(kw["alignment"])]

        # 通用可选参数
        if kw.get("alignment_size") is not None:
            cmd += ["-A", str(kw["alignment_size"])]
        if kw.get("placement_size") is not None:
            cmd += ["-P", str(kw["placement_size"])]
        if kw.get("fragment_chunk_size") is not None:
            cmd += ["-F", str(kw["fragment_chunk_size"])]
        if kw.get("config_file"):
            cmd += ["-c", str(kw["config_file"])]
        if kw.get("output_prefix"):
            cmd += ["-o", str(kw["output_prefix"])]
        if kw.get("outdir"):
            cmd += ["-d", str(kw["outdir"])]

        # 自动注入线程与临时目录
        cmd += ["-x", str(threads), "-p", str(tmpdir)]

        # 高级透传（慎用）
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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 --cpu）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 -p）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="sepp-skill",
        description="sepp native 技能驱动（SEPP 系统发育放置 / UPP 比对；自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-t", "--tree", help="参考系统发育树（Newick）")
    pr.add_argument("-a", "--alignment", help="参考比对（FASTA）")
    pr.add_argument("-f", "--fragment", help="待放置片段序列（FASTA）")
    pr.add_argument("-r", "--raxml-info", help="RAxML_info 文件（可选）")
    pr.add_argument("-A", "--alignment-size", type=int, help="最大比对子集大小（默认 10）")
    pr.add_argument("-P", "--placement-size", type=int, help="最大放置子集大小")
    pr.add_argument("-F", "--fragment-chunk-size", type=int, help="片段分块大小")
    pr.add_argument("-c", "--config-file", help="SEPP 配置文件")
    pr.add_argument("-o", "--output-prefix", help="输出文件前缀（默认 output）")
    pr.add_argument("-d", "--outdir", help="输出目录（完整路径）")
    pr.add_argument("--extra-args", help="透传给 run_sepp.py 的额外参数")
    _add_runtime_opts(pr)

    # upp
    pu = sub.add_parser("upp", help=SUBCOMMANDS["upp"])
    pu.add_argument("-s", "--sequence-file", help="未比对序列文件（FASTA）")
    pu.add_argument("-t", "--tree", help="backbone 树（可选）")
    pu.add_argument("-a", "--alignment", help="backbone 比对（可选）")
    pu.add_argument("-A", "--alignment-size", type=int, help="最大比对子集大小（默认 10）")
    pu.add_argument("-c", "--config-file", help="UPP 配置文件")
    pu.add_argument("-o", "--output-prefix", help="输出文件前缀（默认 output）")
    pu.add_argument("-d", "--outdir", help="输出目录（完整路径）")
    pu.add_argument("--extra-args", help="透传给 run_upp.py 的额外参数")
    _add_runtime_opts(pu)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = SeppSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SeppSkill()
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
