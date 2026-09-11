#!/usr/bin/env python3
"""MAFFT native 标准入口驱动（多序列比对）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align input.fa --threads 8                          # 结果 FASTA 走 stdout（默认 --auto）
   python main.py align -i input.fa -o aligned.fa --threads 8         # -o 由驱动把 stdout 写盘
   python main.py align input.fa --method linsi --threads 8 -o ali.fa # 高精度 L-INS-i
   python main.py version                                             # 打印 mafft --version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程与临时目录（--tmpdir，同时设 TMPDIR）。
注意：MAFFT 的线程参数是 `--thread N`（不是 --threads）；驱动对外的运行期选项仍是 --threads，
构建命令行时翻译为 --thread。

MAFFT 本体无 `-o`（比对结果只写 stdout）；-o/--output 由驱动捕获 stdout 后落盘。
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
    "align": "mafft：多序列比对（FASTA → 等长比对 FASTA），默认 --auto 自动选择策略，缺省输出到 stdout",
    "version": "mafft --version：打印 MAFFT 版本信息",
}


class MafftSkill(base.SkillBase):
    software = "mafft"
    binary = "mafft"

    # 高精度别名（等价于官方 linsi/einsi/ginsi 入口脚本）→ mafft 原生选项组合
    METHODS = {
        "linsi": ["--maxiterate", "1000", "--localpair"],
        "einsi": ["--maxiterate", "1000", "--genafpair"],
        "ginsi": ["--maxiterate", "1000", "--globalpair"],
    }

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/mafft/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 mafft 命令行。"""
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "align":
            inp = kw.get("input")
            if not inp:
                raise RuntimeError("align 需要 input（输入 FASTA，位置参数或 -i/--input）")
            # MAFFT 线程参数为 --thread（单数）
            cmd: list[str] = [self._resolve_binary(), "--thread", str(threads)]

            method = kw.get("method")
            if method:
                key = str(method).strip()
                if key.lower() in self.METHODS:
                    # 高精度别名：linsi/einsi/ginsi → 原生选项组合（隐含不使用 --auto）
                    cmd += self.METHODS[key.lower()]
                elif key.lower() == "auto":
                    cmd += ["--auto"]
                else:
                    # 其它取值按原始 mafft 选项透传（高级用法）
                    cmd += key.split()
            elif kw.get("auto", True):
                # 默认 --auto：自动按序列数与长度选择策略
                cmd += ["--auto"]

            # 高级透传（慎用）
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()

            # 输入 FASTA 作为末尾位置参数（mafft 结果为 stdout）
            cmd.append(str(inp))
        elif subcommand == "version":
            cmd = [self._resolve_binary(), "--version"]
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mafft-skill",
        description="MAFFT native 技能驱动（自动线程/临时目录；多序列比对）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align: mafft [--thread N] [--auto | --method M] input.fa > aligned.fa
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("input", nargs="?", help="输入序列 FASTA（多序列核酸/氨基酸；位置参数或 -i/--input）")
    pa.add_argument("-i", "--input", dest="input_opt", help="输入序列 FASTA（与位置参数等价）")
    pa.add_argument("-o", "--output", help="比对结果输出文件（默认 stdout；由驱动写盘）")
    pa.add_argument(
        "--auto", action=argparse.BooleanOptionalAction, default=True,
        help="启用 mafft --auto 自动选择策略（默认开；--no-auto 关闭，走默认 FFT-NS-2 高速模式）",
    )
    pa.add_argument(
        "--method",
        help="高精度模式：linsi|einsi|ginsi（映射为 --maxiterate 1000 + localpair/genafpair/globalpair）；"
             "写 auto 等价 --auto；其它取值作为原始 mafft 选项透传（高级用法，慎用）",
    )
    pa.add_argument("--extra-args", dest="extra_args", help="透传给 mafft 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pa)

    # version: mafft --version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 mafft 的 --thread N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = MafftSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MafftSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads
    # 位置参数与 -i/--input 二选一：位置参数优先，其次 -i
    if not kw.get("input") and kw.get("input_opt"):
        kw["input"] = kw["input_opt"]
    kw.pop("input_opt", None)

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # align 默认写 stdout；-o/--output 由驱动落盘（mafft 本体无 -o）
    output_file = getattr(ns, "output", None)
    if ns.subcommand == "align" and output_file:
        Path(output_file).write_text(result.stdout)
    else:
        if result.stdout:
            sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
