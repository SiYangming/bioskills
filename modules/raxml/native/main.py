#!/usr/bin/env python3
"""raxml native 标准入口驱动（standard-RAxML v8.2.x）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py ml_bootstrap -s msa.phy -m GTRGAMMA -n out_codon -# 100 -T 8
   python main.py ml_search -s msa.phy -m PROTGAMMAILGX -n out_protein -T 8
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  ml_bootstrap  raxmlHPC-PTHREADS-SSE3 -f a -x <seed> -p <seed> -# <n> -m <model> -s <msa> -n <name> -T <threads>
  ml_search     raxmlHPC-PTHREADS-SSE3 -f d -p <seed> -m <model> -s <msa> -n <name> -T <threads>
  version       raxmlHPC-PTHREADS-SSE3 -v
RAxML 为 CPU 密集工具：驱动按线程优先级注入 -T（--threads > per_subcommand_threads > default_cpus）。
HYBRID（MPI）版本需 MPICH，见 README；execution.binary 登记 SSE3 PTHREADS 版代表性入口。
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
    "ml_bootstrap": "ML 树搜索 + 快速 bootstrap（-f a；-x/-p/-#/-m/-T）",
    "ml_search": "仅 ML 树搜索（-f d；-p/-m/-T）",
    "version": "打印 RAxML 版本（-v）",
}


class RaxmlSkill(base.SkillBase):
    software = "raxml"
    binary = "raxmlHPC-PTHREADS-SSE3"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 RAxML 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()

        if subcommand == "version":
            return [binary, "-v"]

        msa = kw.get("msa") or kw.get("input")
        if not msa:
            raise ValueError(f"{subcommand} 缺少必填参数 msa（输入比对，-s）")

        threads = self._effective_threads(subcommand, kw.get("threads"))
        model = kw.get("model") or "GTRGAMMA"
        name = kw.get("name") or "out"
        cmd: list[str] = [binary]

        if subcommand == "ml_bootstrap":
            cmd += [
                "-f", "a",
                "-x", str(kw.get("bootstrap_seed", 12345)),
                "-p", str(kw.get("parsimony_seed", 12345)),
                "-#", str(kw.get("bootstrap_reps", 100)),
            ]
        else:  # ml_search
            cmd += ["-f", "d", "-p", str(kw.get("parsimony_seed", 12345))]

        cmd += ["-m", str(model), "-s", str(msa), "-n", str(name)]
        if kw.get("output_dir"):
            cmd += ["-w", str(kw["output_dir"])]
        cmd += ["-T", str(threads)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="raxml-skill",
        description="raxml native 技能驱动（standard-RAxML v8.2.x，自动注入 -T）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _add_common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("-s", "--msa", help="输入多序列比对（Phylip/FASTA）")
        sp.add_argument("-m", "--model", default="GTRGAMMA",
                        help="进化模型（核酸/密码子 GTRGAMMA；蛋白质 PROTGAMMAILGX 等）")
        sp.add_argument("-n", "--name", default="out", help="输出文件前缀（默认 out）")
        sp.add_argument("-w", "--output-dir", dest="output_dir", help="输出目录（RAxML -w）")
        sp.add_argument("--parsimony-seed", type=int, help="初始树/似然搜索随机种子（-p，默认 12345）")
        sp.add_argument("--extra-args", help="透传给 RAxML 的额外参数")

    # ml_bootstrap
    pb = sub.add_parser("ml_bootstrap", help=SUBCOMMANDS["ml_bootstrap"])
    _add_common(pb)
    pb.add_argument("-x", "--bootstrap-seed", type=int, help="bootstrap 随机种子（-x，默认 12345）")
    pb.add_argument("-#", "--bootstrap-reps", type=int, help="bootstrap 重复次数（-#，默认 100）")
    _add_runtime_opts(pb)

    # ml_search
    pm = sub.add_parser("ml_search", help=SUBCOMMANDS["ml_search"])
    _add_common(pm)
    _add_runtime_opts(pm)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -T；默认 8）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = RaxmlSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RaxmlSkill()
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
