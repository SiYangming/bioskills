#!/usr/bin/env python3
"""iqtree native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py ml allSingleCopyOrthologsAlign.Protein.phy -m MFP -bb 1000 -alrt 1000 --threads 8 -pre out_protein
   python main.py ml allSingleCopyOrthologsAlign.Protein.phy -m LG+G4 -bb 1000 --threads 8
   python main.py model allSingleCopyOrthologsAlign.Protein.phy -pre modelfinder
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（IQ-TREE v1.6.12；该版线程参数为 -nt）：
  ml     iqtree -s <aln> -m <MFP|model> [-bb <n>] [-alrt <n>] [-t <tree>] -nt N [-pre <prefix>]
  model  iqtree -s <aln> -m MF [-t <tree>] -nt N [-pre <prefix>]
所有子命令自动注入线程（-nt）与临时目录优化。
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
    "ml": "ML 建树：iqtree -s <aln> -m MFP -bb <n> -alrt <n> -nt N（ModelFinder Plus + UFBoot + aLRT）",
    "model": "仅模型选择：iqtree -s <aln> -m MF -nt N（ModelFinder，不建树）",
}


class IqtreeSkill(base.SkillBase):
    software = "iqtree"
    binary = "iqtree"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 iqtree 命令行（v1.6.12 用 -nt 指定线程）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        aln = kw.get("input")
        if not aln:
            raise ValueError("缺少必填参数 input（-s 输入多序列比对）")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "ml":
            model = kw.get("model") or "MFP"
        else:  # model
            model = kw.get("model") or "MF"

        cmd: list[str] = [binary, "-s", str(aln), "-m", str(model)]

        if subcommand == "ml":
            bb = kw.get("bootstrap")
            if bb:  # None / 0 表示不注入 -bb
                cmd += ["-bb", str(bb)]
            if kw.get("alrt"):
                cmd += ["-alrt", str(kw["alrt"])]

        if kw.get("tree"):
            cmd += ["-t", str(kw["tree"])]

        cmd += ["-nt", str(threads)]

        if kw.get("prefix"):
            cmd += ["-pre", str(kw["prefix"])]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -nt）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="iqtree-skill",
        description="iqtree native 技能驱动（最大似然建树 / 模型选择；自动注入 -nt 线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pm = sub.add_parser("ml", help=SUBCOMMANDS["ml"])
    pm.add_argument("input", help="输入多序列比对（PHYLIP/FASTA）")
    pm.add_argument("-m", "--model", help="进化模型（默认 MFP=ModelFinder Plus）")
    pm.add_argument("-bb", "--bootstrap", type=int, default=1000,
                    help="超快 bootstrap 重复次数（默认 1000；0 关闭）")
    pm.add_argument("-alrt", "--alrt", type=int, help="aLRT 重复次数（如 1000）")
    pm.add_argument("-t", "--tree", help="起始树文件（Newick）")
    pm.add_argument("-pre", "--prefix", help="输出文件前缀")
    pm.add_argument("--extra-args", help="透传给 iqtree 的额外参数")
    _add_runtime_opts(pm)

    pd = sub.add_parser("model", help=SUBCOMMANDS["model"])
    pd.add_argument("input", help="输入多序列比对（PHYLIP/FASTA）")
    pd.add_argument("-m", "--model", help="模型（默认 MF=仅 ModelFinder）")
    pd.add_argument("-t", "--tree", help="起始树文件（Newick）")
    pd.add_argument("-pre", "--prefix", help="输出文件前缀")
    pd.add_argument("--extra-args", help="透传给 iqtree 的额外参数")
    _add_runtime_opts(pd)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = IqtreeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = IqtreeSkill()
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
