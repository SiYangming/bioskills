#!/usr/bin/env python3
"""isolasso native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble  alignments.bam -o sample        # 端到端：SAM/BAM -> <prefix>.pred.gtf
   python main.py processsam alignments.sam -o sample        # SAM/BAM -> sample.instance
   python main.py isolasso   sample.instance -o sample       # instance -> sample.pred
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（IsoLasso v2.6.1 官方 bin/）：
  assemble   runlasso.py [-o <prefix>] <input.sam|.bam|.instance>
             （内部：processsam -> isolasso -> pred2gtf|sortgtf，产出 <prefix>.pred.gtf）
  processsam processsam [-o <instance>] <input.sam>       （SAM/BAM -> .instance）
  isolasso   isolasso   [-o <prefix>] <input.instance>    （LASSO 求解 -> .pred）
注意：IsoLasso 求解为单线程，--threads 仅为接口一致性保留（不注入命令行；make -j 仅影响编译）。
BAM 输入需系统 PATH 中有 samtools（runlasso.py 会用 `samtools view` 管道）。
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
    "assemble": "端到端转录本组装（runlasso.py：SAM/BAM/instance -> <prefix>.pred.gtf）",
    "processsam": "SAM/BAM 转 instance（processsam）",
    "isolasso": "LASSO 求解 instance -> .pred（isolasso）",
}

# 子命令 -> 官方 bin/ 下的可执行文件
SUBCOMMAND_BINARY = {
    "assemble": "runlasso.py",
    "processsam": "processsam",
    "isolasso": "isolasso",
}


class IsoLasssoSkill(base.SkillBase):
    software = "isolasso"
    binary = "runlasso.py"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析可执行文件（测试可 monkeypatch 本方法）。"""
        name = name or self.binary
        path = which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{name}'，请先编译安装 IsoLasso（见 README「环境安装」）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 IsoLasso 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(SUBCOMMAND_BINARY[subcommand])
        input_file = kw.get("input")
        if not input_file:
            raise ValueError(f"{subcommand} 缺少必填参数 input（位置参数）")

        cmd: list[str] = [binary]
        # runlasso.py / isolasso 支持 -o/--prefix；processsam 输出默认 <input>.instance，-o 指定输出
        if kw.get("output_prefix"):
            cmd += ["-o", str(kw["output_prefix"])]

        # 高级透传需在位置参数之前（runlasso.py 解析 --prefix 时会遍历到倒第二个参数）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        cmd.append(str(input_file))

        # 注：IsoLasso 单线程，--threads 不注入命令行
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
    p.add_argument("--threads", type=int, help="线程数（接口兼容；IsoLasso 单线程，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="isolasso-skill",
        description="isolasso native 技能驱动（LASSO 回归 RNA-seq 转录本组装，v2.6.1）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("input", help="SAM/BAM/instance 输入（BAM 需 PATH 中有 samtools）")
    pa.add_argument("-o", "--output-prefix", help="输出前缀（产出 <prefix>.pred.gtf）")
    pa.add_argument("--extra-args", help="透传给 runlasso.py 的额外参数")
    _add_runtime_opts(pa)

    ps = sub.add_parser("processsam", help=SUBCOMMANDS["processsam"])
    ps.add_argument("input", help="SAM 输入")
    ps.add_argument("-o", "--output-prefix", help="输出 instance 前缀（默认 <input>.instance）")
    ps.add_argument("--extra-args", help="透传给 processsam 的额外参数")
    _add_runtime_opts(ps)

    pi = sub.add_parser("isolasso", help=SUBCOMMANDS["isolasso"])
    pi.add_argument("input", help=".instance 输入")
    pi.add_argument("-o", "--output-prefix", help="输出前缀（产出 <prefix>.pred）")
    pi.add_argument("--extra-args", help="透传给 isolasso 的额外参数")
    _add_runtime_opts(pi)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = IsoLasssoSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = IsoLasssoSkill()
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
