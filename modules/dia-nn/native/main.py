#!/usr/bin/env python3
"""dia-nn native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   # 两步式典型用法（先建预测库，再分析 .raw/.mzML 数据）：
   python main.py lib --fasta uniprot_proteome.fasta --out-lib report-lib --threads 8
   python main.py run --fasta uniprot_proteome.fasta --lib report-lib.predicted.speclib \
       --dir raw/ --out report.tsv --qvalue 0.01 --matrices --threads 8
   # 或一步式：run 直接 --fasta-search 搜 FASTA（不走预建库）
   python main.py run --fasta uniprot_proteome.fasta --dir raw/ --out report.tsv --fasta-search
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（diann 官方 CLI；DIA-NN 为 DIA 质谱分析软件，run/lib 只是对同一 diann
二进制不同旗标组合的封装）：
  lib  diann --fasta <f> --predictor --out-lib <prefix> [--threads]   # in-silico 预测库生成
  run  diann [--fasta <f>] [--lib <speclib>] --dir <rawdir> --out <tsv>
             --qvalue 0.01 [--predictor|--fasta-search] [--matrices] [--relaxed-prot-inf]
             [--reanalyse] [--out-lib <prefix>] [--temp <dir>] --threads N
所有子命令自动注入线程（--threads）与临时目录优化（TMPDIR；--temp 透传 diann）。
说明：DIA-NN 官方仅分发 Linux 二进制（.NET 8 框架依赖 + libtorch），无真实 .raw
      数据无法合成运行，测试见 native/test/run_test.sh（argv 构造断言）。
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
    "lib": "in-silico 预测谱图库生成：diann --fasta <f> --predictor --out-lib <prefix>",
    "run": "DIA 数据分析（search/quant）：diann [--fasta|--lib] --dir <rawdir> --out <tsv> --qvalue ...",
}

# lib 的 argparse alias
LIB_ALIASES = ["library"]


class DiaNNSkill(base.SkillBase):
    software = "dia-nn"
    binary = "diann"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 diann 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary]
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "lib":
            # 一步：FASTA -> in-silico 预测谱图库（输出 <prefix>.predicted.speclib）
            fasta = kw.get("fasta")
            if not fasta:
                raise ValueError("lib 缺少必填参数 fasta（蛋白 FASTA 数据库）")
            out_lib = kw.get("out_lib")
            if not out_lib:
                raise ValueError("lib 缺少必填参数 out_lib（输出前缀，实际产出 <prefix>.predicted.speclib）")
            cmd += ["--fasta", str(fasta), "--out-lib", str(out_lib)]
            # 预测器：DIA-NN 库生成默认启用深度学习预测器
            if kw.get("predictor", True):
                cmd.append("--predictor")
            if kw.get("fasta_search"):
                cmd.append("--fasta-search")

        elif subcommand == "run":
            # 分析：raw(.d/mzML/Thermo RAW) -> 定量报告 TSV
            fasta = kw.get("fasta")
            lib = kw.get("lib")
            if not fasta and not lib:
                raise ValueError("run 需至少给出 fasta（配 --fasta-search/--predictor）或 lib（现有谱图库）之一")
            rawdir = kw.get("dir")
            if not rawdir:
                raise ValueError("run 缺少必填参数 dir（含 .raw/.d/.mzML 的输入目录）")
            out = kw.get("out")
            if not out:
                raise ValueError("run 缺少必填参数 out（输出报告 TSV 路径）")
            if fasta:
                cmd += ["--fasta", str(fasta)]
            if lib:
                cmd += ["--lib", str(lib)]
            cmd += ["--dir", str(rawdir), "--out", str(out)]
            if kw.get("predictor"):
                cmd.append("--predictor")
            if kw.get("fasta_search"):
                cmd.append("--fasta-search")
            if kw.get("matrices"):
                cmd.append("--matrices")
            if kw.get("relaxed_prot_inf"):
                cmd.append("--relaxed-prot-inf")
            if kw.get("reanalyse"):
                cmd.append("--reanalyse")
            if kw.get("out_lib"):
                cmd += ["--out-lib", str(kw["out_lib"])]
            if kw.get("temp"):
                cmd += ["--temp", str(kw["temp"])]
            # qvalue 默认 0.01（DIA-NN 官方默认），显式透传便于 Agent 修改
            cmd += ["--qvalue", str(kw.get("qvalue", 0.01))]

        cmd += ["--threads", str(threads)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dia-nn-skill",
        description="dia-nn native 技能驱动（DIA-NN 2.6.1；自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # lib（library）：in-silico 预测谱图库生成
    pl = sub.add_parser("lib", aliases=LIB_ALIASES, help=SUBCOMMANDS["lib"])
    pl.add_argument("--fasta", "-f", help="蛋白 FASTA 数据库（uniprot 等）")
    pl.add_argument("--out-lib", help="输出前缀（实际产出 <prefix>.predicted.speclib）")
    pl.add_argument("--predictor", dest="predictor", action="store_true",
                    help="使用深度学习预测器（默认开启；加 --no-predictor 关闭）")
    pl.add_argument("--no-predictor", dest="predictor", action="store_false",
                    help="关闭 --predictor")
    pl.set_defaults(predictor=True)
    pl.add_argument("--fasta-search", action="store_true", help="同时直接搜 FASTA")
    pl.add_argument("--extra-args", help="透传给 diann 的额外参数")
    _add_runtime_opts(pl)

    # run：DIA 数据分析
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("--fasta", "-f", help="蛋白 FASTA 数据库（无 --lib 时配合 --fasta-search/--predictor）")
    pr.add_argument("--lib", help="现有谱图库 speclib（如 report-lib.predicted.speclib）")
    pr.add_argument("--dir", required=True, help="含质谱原始数据（.raw/.d/.mzML）的目录")
    pr.add_argument("--out", required=True, help="输出报告 TSV 路径")
    pr.add_argument("--qvalue", type=float, default=0.01, help="Q-value 阈值（默认 0.01）")
    pr.add_argument("--predictor", action="store_true", help="使用深度学习预测器")
    pr.add_argument("--fasta-search", action="store_true", help="直接对 FASTA 搜索（无库分析）")
    pr.add_argument("--matrices", action="store_true", help="输出定量矩阵（pg/pr/gg_matrix.tsv）")
    pr.add_argument("--relaxed-prot-inf", action="store_true", help="宽松蛋白推断")
    pr.add_argument("--reanalyse", action="store_true", help="reanalyse 模式（配合已有结果）")
    pr.add_argument("--out-lib", help="额外输出预测库前缀（可选）")
    pr.add_argument("--temp", help="DIA-NN 中间/quant 文件目录（--temp，默认随 TMPDIR）")
    pr.add_argument("--extra-args", help="透传给 diann 的额外参数")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = DiaNNSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2
    # alias 归一：lib 的别名 library 落到子命令键 lib
    if ns.subcommand in LIB_ALIASES:
        ns.subcommand = "lib"

    skill = DiaNNSkill()
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

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
