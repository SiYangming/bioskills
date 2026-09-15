#!/usr/bin/env python3
"""sspace native 标准入口驱动（SSPACE STANDARD v3.0；BaseClear scaffold 连接工具）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py scaffold -l library.txt -s genome.fasta -x 0 -b SSPACE_OUT --threads 4
   python main.py sam2tab -i reads.sorted.sam -o fragment.tab
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（脚本均以 perl 调起，SSPACE 主脚本无标准 --version）：
  scaffold  perl SSPACE_Standard_v3.0.pl -l <library> -s <contigs> -x <0|1> -T <threads> -b <base> [-k <n>]
  sam2tab   perl sam_bam2tab.pl <in.sam> <postfix1> <postfix2> <out.tab>
所有子命令自动注入线程（-T）与临时目录优化。
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
    "scaffold": "contigs + 配对文库 -> 更长的 scaffolds（SSPACE_Standard_v3.0.pl -l <library> -s <contigs> -x <0|1> -T <threads> -b <base>）",
    "sam2tab": "SAM/BAM -> TAB 配对信息（sam_bam2tab.pl <in.sam> <postfix1> <postfix2> <out.tab>）",
}

# 子命令 -> 真实可执行脚本名
_BINARIES = {"scaffold": "SSPACE_Standard_v3.0.pl", "sam2tab": "sam_bam2tab.pl"}


class SspaceSkill(base.SkillBase):
    software = "sspace"
    binary = "SSPACE_Standard_v3.0.pl"

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令解析脚本路径（SSPACE_Standard_v3.0.pl / sam_bam2tab.pl）。"""
        try:
            bin_name = _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到脚本 '{bin_name}'：请先安装 SSPACE STANDARD v3.0 并把其目录加入 "
                f"PATH（自建镜像 / native/install.sh；见 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 SSPACE 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        script = self._resolve_sub_binary(subcommand)

        if subcommand == "scaffold":
            library = kw.get("library")
            genome = kw.get("genome")
            if not library:
                raise ValueError("scaffold 缺少必填参数 library（-l 文库文件）")
            if not genome:
                raise ValueError("scaffold 缺少必填参数 genome（-s contigs FASTA）")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            base_name = kw.get("base_name") or "standard_output"
            cmd: list[str] = [
                "perl", script,
                "-l", self._abspath(library),
                "-s", self._abspath(genome),
                "-x", str(int(kw.get("extend", 0) or 0)),
                "-T", str(threads),
                "-b", str(base_name),
            ]
            if kw.get("min_links") is not None:
                cmd += ["-k", str(int(kw["min_links"]))]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        # sam2tab
        inp = kw.get("input")
        out = kw.get("output")
        if not inp:
            raise ValueError("sam2tab 缺少必填参数 input（SAM/BAM，需按 read name 排序）")
        if not out:
            raise ValueError("sam2tab 缺少必填参数 output（输出 TAB 文件）")
        return [
            "perl", script,
            self._abspath(inp),
            str(kw.get("postfix1") or "/1"),
            str(kw.get("postfix2") or "/2"),
            self._abspath(out),
        ]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="sspace-skill",
        description="SSPACE STANDARD v3.0 native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    ps = sub.add_parser("scaffold", help=SUBCOMMANDS["scaffold"])
    ps.add_argument("-l", "--library", required=True, help="文库文件（LibName Aligner R1 R2 insert error orientation）")
    ps.add_argument("-s", "--genome", required=True, help="输入 contigs FASTA")
    ps.add_argument("-b", "--base-name", help="输出前缀（默认 standard_output）")
    ps.add_argument("-x", "--extend", type=int, default=0, help="是否延伸 contigs（1=是，0=否，默认 0）")
    ps.add_argument("-k", "--min-links", type=int, help="最小 read-pair 连接数（默认 5）")
    ps.add_argument("--extra-args", help="透传给 SSPACE_Standard_v3.0.pl 的额外参数")
    _add_runtime_opts(ps, threads_flag="scaffold")

    pt = sub.add_parser("sam2tab", help=SUBCOMMANDS["sam2tab"])
    pt.add_argument("input", nargs="?", help="输入 SAM/BAM（别名 --input）")
    pt.add_argument("-i", "--input", dest="input_opt", help="输入 SAM/BAM 的别名")
    pt.add_argument("-o", "--output", required=True, help="输出 TAB 文件")
    pt.add_argument("--postfix1", default="/1", help="R1 read 名后缀（默认 /1）")
    pt.add_argument("--postfix2", default="/2", help="R2 read 名后缀（默认 /2）")
    _add_runtime_opts(pt, threads_flag="sam2tab")

    return p


def _add_runtime_opts(p: argparse.ArgumentParser, threads_flag: str = "scaffold") -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    if threads_flag == "scaffold":
        p.add_argument("--threads", type=int, help="覆盖默认线程数（SSPACE -T）")
    else:
        p.add_argument("--threads", type=int, help="线程数（sam2tab 无多线程，仅记录）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = SspaceSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SspaceSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    skip = ("subcommand", "threads", "tmpdir", "input", "input_opt")
    kw = {k: v for k, v in vars(ns).items() if k not in skip and v is not None}
    kw["threads"] = ns.threads
    if ns.subcommand == "sam2tab":
        kw["input"] = ns.input_opt or ns.input

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    result = base.run_command(cmd, env=skill.env_vars, check=False)
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
