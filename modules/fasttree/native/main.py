#!/usr/bin/env python3
"""fasttree native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py protein allSingleCopyOrthologsAlign.Protein.fasta -out tree.nwk
   python main.py nucleotide allSingleCopyOrthologsAlign.Codon.fasta --gtr -out tree.nwk
   python main.py boot allSingleCopyOrthologsAlign.Protein.fasta -boot 1000 -out tree.nwk
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  protein     FastTree [-gamma] [-pseudo] [-fastest] [-out <tree>] [-log <log>] [-quiet] <aln>
  nucleotide  FastTree -nt [-gtr] [-gamma] ... <aln>
  boot        FastTree [-nt] [-gtr] -boot <n> [-out <tree>] ... <aln>
FastTree 单线程，--threads 仅作统一接口与上层调度参考，不注入命令行。
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
    "protein": "蛋白比对建树：FastTree [-out <tree>] <aln>（默认 JTT+CAT）",
    "nucleotide": "核酸比对建树：FastTree -nt [-gtr] [-out <tree>] <aln>（GTR+CAT / JTT+CAT）",
    "boot": "局部支持度：FastTree [-nt] [-gtr] -boot <n> [-out <tree>] <aln>（SH-like 重采样）",
}


class FasttreeSkill(base.SkillBase):
    software = "fasttree"
    binary = "FastTree"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（FastTree 单线程，仅调度参考）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 FastTree 命令行（选项必须位于比对文件之前）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        aln = kw.get("input")
        if not aln:
            raise ValueError("缺少必填参数 input（输入多序列比对）")

        binary = self._resolve_binary()
        # FastTree 单线程，仅解析线程优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        flags: list[str] = []
        is_nucleotide = subcommand == "nucleotide" or (subcommand == "boot" and kw.get("nucleotide"))
        if is_nucleotide:
            flags.append("-nt")
        if kw.get("gtr"):
            flags.append("-gtr")
        if subcommand == "boot":
            reps = kw.get("bootstrap") or 1000
            flags += ["-boot", str(reps)]
        if kw.get("gamma"):
            flags.append("-gamma")
        if kw.get("pseudo"):
            flags.append("-pseudo")
        if kw.get("fastest"):
            flags.append("-fastest")
        if kw.get("intree"):
            flags += ["-intree", str(kw["intree"])]
        if kw.get("output"):
            flags += ["-out", str(kw["output"])]
        if kw.get("log"):
            flags += ["-log", str(kw["log"])]
        if kw.get("quiet", True):
            flags.append("-quiet")

        extra = kw.get("extra_args")
        if extra:
            flags += str(extra).split()

        return [binary, *flags, str(aln)]

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（FastTree 默认写 stdout，由 main() 输出）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（FastTree 单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加 FastTree 通用参数。"""
    p.add_argument("input", help="输入多序列比对（FASTA 或 PHYLIP interleaved）")
    p.add_argument("-out", "--output", help="输出 Newick 树文件（缺省 stdout）")
    p.add_argument("-log", "--log", help="中间树/参数/模型详情日志")
    p.add_argument("--gamma", action="store_true", help="用 gamma 分布建模位点异质性")
    p.add_argument("--pseudo", action="store_true", help="使用伪计数（推荐高缺 gap 序列）")
    p.add_argument("--fastest", action="store_true", help="加速邻居连接阶段并降低内存")
    p.add_argument("-intree", "--intree", help="起始树文件（集合）")
    p.add_argument("--no-quiet", dest="quiet", action="store_false", help="不抑制进度/统计输出")
    p.add_argument("--extra-args", help="透传给 FastTree 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fasttree-skill",
        description="fasttree native 技能驱动（超快近似最大似然建树；FastTree 单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("protein", help=SUBCOMMANDS["protein"])
    _add_common_opts(pp)
    _add_runtime_opts(pp)

    pn = sub.add_parser("nucleotide", help=SUBCOMMANDS["nucleotide"])
    pn.add_argument("-gtr", "--gtr", action="store_true", help="广义时间可逆模型（核酸）")
    _add_common_opts(pn)
    _add_runtime_opts(pn)

    pb = sub.add_parser("boot", help=SUBCOMMANDS["boot"])
    pb.add_argument("-boot", "--bootstrap", type=int, default=1000,
                    help="局部支持度重采样次数（默认 1000）")
    pb.add_argument("--nucleotide", action="store_true", help="输入为核酸序列（-nt）")
    pb.add_argument("-gtr", "--gtr", action="store_true", help="广义时间可逆模型（核酸）")
    _add_common_opts(pb)
    _add_runtime_opts(pb)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = FasttreeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FasttreeSkill()
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
