#!/usr/bin/env python3
"""signalp native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict proteins.fasta -org euk -batch 30000 --gff3
   python main.py mature  proteins.fasta -org euk -prefix proteins
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  predict  signalp -org <euk|gram+|gram-|archaea> -fasta <in> [-batch N] [-gff3] [-prefix <p>]
  mature   同上并追加 -mature（仅对成熟蛋白/已去信号肽序列预测）
注意：SignalP 5.0 本体单线程（-batch 分批），--threads 仅作统一接口与上层调度参考，不注入命令行。
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
    "predict": "蛋白质 FASTA -> 信号肽预测（signalp -org <euk|gram+|gram-|archaea> -fasta）",
    "mature": "成熟蛋白 FASTA -> 信号肽预测（在 predict 基础上追加 -mature）",
}

# -org 合法取值（archaea 官方写法为 arch）
ORG_ALIASES = {
    "euk": "euk",
    "archaea": "arch",
    "arch": "arch",
    "gram+": "gram+",
    "gram-": "gram-",
}

DEFAULT_BATCH = 30000


class SignalpSkill(base.SkillBase):
    software = "signalp"
    binary = "signalp"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 signalp 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        fasta = kw.get("fasta") or kw.get("input")
        if not fasta:
            raise ValueError(f"{subcommand} 缺少必填参数 fasta（输入蛋白质 FASTA）")

        org = kw.get("organism")
        if org:
            key = str(org).lower()
            if key not in ORG_ALIASES:
                raise ValueError(f"-org 仅支持 euk|gram+|gram-|archaea（收到: {org}）")
            cmd += ["-org", ORG_ALIASES[key]]

        cmd += ["-fasta", str(fasta)]

        batch = kw.get("batch")
        if batch is not None:
            cmd += ["-batch", str(batch)]

        if kw.get("gff3"):
            cmd += ["-gff3"]

        if subcommand == "mature" or kw.get("mature"):
            cmd += ["-mature"]

        if kw.get("prefix"):
            cmd += ["-prefix", str(kw["prefix"])]

        # 线程：SignalP 单线程（-batch 分批），仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（signalp 自行写输出文件，此处透传 stdout/stderr）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """signalp 公共选项（-org/-fasta/-batch/-gff3/-prefix）。"""
    p.add_argument("input", nargs="?", help="输入蛋白质 FASTA（别名 --fasta）")
    p.add_argument("--fasta", help="输入蛋白质 FASTA 的别名")
    p.add_argument("-org", "--organism", help="生物类群：euk|gram+|gram-|archaea")
    p.add_argument("-batch", type=int, default=None,
                   help=f"每批处理序列数（默认 {DEFAULT_BATCH}；减小可降低内存占用）")
    p.add_argument("--gff3", action="store_true", help="追加 GFF3 格式输出")
    p.add_argument("-prefix", "--prefix", help="输出文件前缀（默认取输入 FASTA 文件名）")
    p.add_argument("--extra-args", help="透传给 signalp 的额外参数")


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（SignalP 单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="signalp-skill",
        description="signalp native 技能驱动（SignalP 5.0 信号肽预测，许可受限需自备 tarball）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    _add_common_opts(pp)
    _add_runtime_opts(pp)

    pm = sub.add_parser("mature", help=SUBCOMMANDS["mature"])
    _add_common_opts(pm)
    _add_runtime_opts(pm)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = SignalpSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SignalpSkill()
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
