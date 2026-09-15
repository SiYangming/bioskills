#!/usr/bin/env python3
"""star-fusion native 标准入口驱动（STAR-Fusion — 融合基因检测，推荐）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py detect --genome_lib_dir /path/CTAT_resource_lib \
       --left_fq reads_1.fastq.gz --right_fq reads_2.fastq.gz --output_dir . --CPU 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐教学文档 3.14.3 / 12.3 STAR-Fusion 示例）：
  STAR-Fusion --genome_lib_dir <CTAT_resource_lib> [--left_fq R1 [--right_fq R2]] \
              --output_dir <dir> --CPU N
STAR-Fusion 主程序为 Perl 脚本（#!/usr/bin/env perl），随 conda 包安装到 PATH；运行前必须准备
CTAT_resource_lib（可从 CTAT 下载或本地构建）。
"""

from __future__ import annotations

import argparse
import json
import shlex
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
    "detect": "STAR-Fusion 融合基因检测（--genome_lib_dir <CTAT_resource_lib> --left_fq R1 [--right_fq R2] --output_dir <dir> --CPU N）",
}


class StarFusionSkill(base.SkillBase):
    software = "star-fusion"
    binary = "STAR-Fusion"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 STAR-Fusion 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

        genome_lib = kw.get("genome_lib_dir")
        left_fq = kw.get("left_fq")
        out = kw.get("output_dir")
        if not genome_lib:
            raise ValueError("detect 缺少必填参数 genome_lib_dir（--genome_lib_dir CTAT 资源库目录）")
        if not left_fq:
            raise ValueError("detect 缺少必填参数 left_fq（--left_fq reads mate1）")
        if not out:
            raise ValueError("detect 缺少必填参数 output_dir（--output_dir 输出目录）")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = [
            binary,
            "--genome_lib_dir", str(genome_lib),
            "--left_fq", str(left_fq),
        ]
        if kw.get("right_fq"):
            cmd += ["--right_fq", str(kw["right_fq"])]
        cmd += ["--output_dir", str(out), "--CPU", str(threads)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射到 STAR-Fusion --CPU）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="star-fusion-skill",
        description="star-fusion native 技能驱动（STAR-Fusion 融合检测；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pd = sub.add_parser("detect", help=SUBCOMMANDS["detect"])
    pd.add_argument("--genome_lib_dir", required=True, help="CTAT 资源库目录（--genome_lib_dir）")
    pd.add_argument("--left_fq", required=True, help="输入 reads mate1（--left_fq）")
    pd.add_argument("--right_fq", help="输入 reads mate2（--right_fq，单端省略）")
    pd.add_argument("--output_dir", required=True, help="输出目录（--output_dir）")
    pd.add_argument("--extra-args", help="透传给 STAR-Fusion 的额外参数（慎用）")
    _add_runtime_opts(pd)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = StarFusionSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = StarFusionSkill()
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
