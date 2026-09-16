#!/usr/bin/env python3
"""genomescope2 native 标准入口驱动（GenomeScope 2.0 / genomescope2 v1.0.0）。

GenomeScope 2.0 从 k-mer 计数直方图（jellyfish histo / KMC 产出）估计基因组大小、杂合度与
重复序列比例，命令行入口为 R 脚本 genomescope.R（conda 安装后在 PATH）：
  genomescope.R -i <histo> -o <outdir> -k <k> [-p <ploidy>] [-l <lambda>] [-n <prefix>]
                [-m <max_kmercov>]

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -i mer_counts.histo -o genomescope -k 21 -p 1 --report genomescope.out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  genomescope.R -i mer_counts.histo -o genomescope -k 21 -p 1 > genomescope.out

前置：genomescope.R 在 PATH（conda genomescope2 安装自带，含 jellyfish 依赖；见 README
「环境安装」）。GenomeScope 为单线程 R 脚本，--threads 仅保留契约、不注入。
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

SUBCOMMANDS = {
    "run": "k-mer 计数直方图 -> 基因组大小/杂合度/重复估计（genomescope.R）",
}


class Genomescope2Skill(base.SkillBase):
    software = "genomescope2"
    binary = "genomescope.R"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 genomescope.R 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        binary = self._resolve_binary()

        if subcommand == "run":
            histogram = kw.get("histogram") or kw.get("input")
            if not histogram:
                raise RuntimeError("run 需要输入直方图 --histogram（-i）")
            outdir = kw.get("output_dir") or kw.get("output")
            if not outdir:
                raise RuntimeError("run 需要输出目录 --output-dir（-o）")
            if kw.get("kmer_size") is None:
                raise RuntimeError("run 需要 --kmer-size（-k）")
            cmd: list[str] = [
                binary,
                "-i", str(histogram),
                "-o", str(outdir),
                "-k", str(int(kw["kmer_size"])),
            ]
            if kw.get("ploidy") is not None:
                cmd += ["-p", str(int(kw["ploidy"]))]
            if kw.get("lambda_init") is not None:
                cmd += ["-l", str(kw["lambda_init"])]
            if kw.get("name_prefix"):
                cmd += ["-n", str(kw["name_prefix"])]
            if kw.get("max_kmercov") is not None:
                cmd += ["-m", str(int(kw["max_kmercov"]))]
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            return cmd

        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genomescope2-skill",
        description="genomescope2 native 技能驱动（k-mer 直方图 → 基因组特征估计）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-i", "--histogram", required=True, help="输入 k-mer 计数直方图")
    pr.add_argument("-o", "--output-dir", required=True, help="输出目录")
    pr.add_argument("-k", "--kmer-size", type=int, required=True, help="k-mer 长度（-k）")
    pr.add_argument("-p", "--ploidy", type=int, default=2, help="倍性（1=单倍体，默认 2）")
    pr.add_argument("-l", "--lambda", dest="lambda_init", type=float,
                    help="平均 k-mer 覆盖度初始猜测（可选）")
    pr.add_argument("-n", "--name-prefix", help="输出文件前缀（可选）")
    pr.add_argument("-m", "--max-kmercov", type=int, help="过滤高频率 k-mer 的覆盖度上限（可选）")
    pr.add_argument("--report", help="将 genomescope.R 的 stdout 报告写入该文件（默认打印）")
    pr.add_argument("--extra-args", help="透传的额外参数")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（GenomeScope 单线程，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = Genomescope2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Genomescope2Skill()
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

    # 报告（stdout）可选写入 --report 文件
    if getattr(ns, "report", None) and result.stdout:
        with open(ns.report, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
