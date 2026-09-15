#!/usr/bin/env python3
"""prodigal native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict -i genome.fna -o genes.gbk -a proteins.faa -d genes.fna -f gff -g 11
   python main.py meta    -i contigs.fna -o genes.gff -f gff
   python main.py train   -i genome.fna -t genome.training -o genes.gbk
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（Prodigal v2.6.3）：
  predict   prodigal -p single -i <input> -o <out> [-a <faa>] [-d <fna>] [-s <score>] [-f <fmt>] [-g <code>]
  meta      prodigal -p meta   -i <input> ... （宏基因组，不做自训练）
  anon      prodigal -p anon   -i <input> ... （使用内置匿名模型）
  train     prodigal -p train  -i <input> -t <training_file> -o <out> ...
注意：Prodigal 为单线程工具，不接受线程参数；--threads 仅为接口一致性保留（不注入命令行）。
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
    "predict": "单基因组原核基因预测（prodigal -p single，自训练模型）",
    "meta": "宏基因组原核基因预测（prodigal -p meta，不做训练）",
    "anon": "匿名模式预测（prodigal -p anon，使用内置匿名模型）",
    "train": "训练模式：导出训练参数文件（prodigal -p train -t <training_file>）",
}

# 子命令 -> Prodigal -p 模式
MODE = {"predict": "single", "meta": "meta", "anon": "anon", "train": "train"}

# 需要训练文件的子命令
NEEDS_TRAINING = {"train"}


class ProdigalSkill(base.SkillBase):
    software = "prodigal"
    binary = "prodigal"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 prodigal 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        input_file = kw.get("input") or kw.get("fasta")
        if not input_file:
            raise ValueError(f"{subcommand} 缺少必填参数 input（-i 输入 FASTA）")

        cmd: list[str] = [binary, "-p", MODE[subcommand], "-i", str(input_file)]

        # 训练模式必须有 -t 训练文件
        if subcommand in NEEDS_TRAINING:
            training_file = kw.get("training_file")
            if not training_file:
                raise ValueError("train 缺少必填参数 training_file（-t 输出训练文件）")
            cmd += ["-t", str(training_file)]
        else:
            # predict/meta/anon 可选复用已有训练文件
            if kw.get("training_file"):
                cmd += ["-t", str(kw["training_file"])]

        if kw.get("output"):
            cmd += ["-o", str(kw["output"])]
        if kw.get("protein"):
            cmd += ["-a", str(kw["protein"])]
        if kw.get("nucleotide"):
            cmd += ["-d", str(kw["nucleotide"])]
        if kw.get("start_score"):
            cmd += ["-s", str(kw["start_score"])]
        if kw.get("format"):
            cmd += ["-f", str(kw["format"])]
        if kw.get("translation_table") is not None:
            cmd += ["-g", str(kw["translation_table"])]
        if kw.get("closed_ends"):
            cmd.append("-c")
        if kw.get("mask_ns"):
            cmd.append("-m")
        if kw.get("quiet"):
            cmd.append("-q")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 注：Prodigal 单线程，--threads 不注入命令行
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
    p.add_argument("--threads", type=int, help="线程数（接口兼容；Prodigal 单线程，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("-o", "--output", help="基因坐标输出文件（默认格式 gbk）")
    p.add_argument("-a", "--protein", help="输出蛋白序列（FASTA）")
    p.add_argument("-d", "--nucleotide", help="输出基因核酸序列（FASTA）")
    p.add_argument("-s", "--start-score", help="输出起始位点打分明细")
    p.add_argument("-f", "--format", help="坐标输出格式：gbk|gff|sqn|sco|none（默认 gbk）")
    p.add_argument("-g", "--translation-table", type=int, help="遗传密码子表（11 标准 / 4 古菌）")
    p.add_argument("-c", "--closed-ends", action="store_true", help="视为完整环状/无缺口")
    p.add_argument("-m", "--mask-ns", action="store_true", help="屏蔽含 N 区域的基因")
    p.add_argument("-q", "--quiet", action="store_true", help="静默模式")
    p.add_argument("--extra-args", help="透传给 prodigal 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="prodigal-skill",
        description="prodigal native 技能驱动（原核基因预测：single/meta/anon/train）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("-i", "--input", required=True, help="输入基因组 FASTA")
    pp.add_argument("-t", "--training-file", help="复用已有训练参数文件（可选）")
    _add_common_opts(pp)
    _add_runtime_opts(pp)

    # meta
    pm = sub.add_parser("meta", help=SUBCOMMANDS["meta"])
    pm.add_argument("-i", "--input", required=True, help="输入宏基因组/contigs FASTA")
    _add_common_opts(pm)
    _add_runtime_opts(pm)

    # anon
    pa = sub.add_parser("anon", help=SUBCOMMANDS["anon"])
    pa.add_argument("-i", "--input", required=True, help="输入基因组 FASTA")
    _add_common_opts(pa)
    _add_runtime_opts(pa)

    # train
    pt = sub.add_parser("train", help=SUBCOMMANDS["train"])
    pt.add_argument("-i", "--input", required=True, help="输入基因组 FASTA")
    pt.add_argument("-t", "--training-file", required=True, help="输出训练参数文件（-t）")
    _add_common_opts(pt)
    _add_runtime_opts(pt)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = ProdigalSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ProdigalSkill()
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
