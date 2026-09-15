#!/usr/bin/env python3
"""ancom native 标准入口驱动（ANCOM，微生物组差异丰度 R 脚本）。

ANCOM 以 R 脚本形态分发（无独立命令行二进制），本驱动用 Rscript 运行同目录
run_ancom.R（参数经临时 params.tsv 传递，规避 R 侧引号转义），先
feature_table_pre_process 预处理，再 ANCOM 检测两组间差异丰度 taxa。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py analyze feature-table.tsv sample-metadata.tsv \
       --sample-var Sample.ID --main-var Subject -o ancom_result.csv
   python main.py analyze table.tsv md.tsv --sample-var SampleID --main-var delivery \
       --group-var delivery --neg-lb -o res.csv
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：R >= 4.0 且已安装 ANCOM 源码依赖（nlme/tidyverse/compositions），
并准备好 ANCOM 代码（--ancom-home / 环境变量 ANCOM_HOME / 默认 ~/software/ANCOM，
见 native/install.sh）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "analyze": "ANCOM 差异丰度分析（feature_table_pre_process 预处理 + ANCOM 主函数，两组比较）",
}


class AncomSkill(base.SkillBase):
    software = "ancom"
    binary = "Rscript"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/ancom/meta.yaml（不在 native/ 下）
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _driver(self) -> Path:
        return _HERE / "run_ancom.R"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """analyze：写 params.tsv 并构造 `Rscript run_ancom.R <params>`。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()
        # 解析线程（ANCOM 为单进程 R 脚本，无对应 flag，仅保证接口/优先级一致）
        self._effective_threads(subcommand, kw.get("threads"))

        feature_table = kw.get("feature_table")
        metadata = kw.get("metadata")
        output = kw.get("output")
        sample_var = kw.get("sample_var")
        main_var = kw.get("main_var")
        if not (feature_table and metadata):
            raise ValueError("analyze 需要 feature_table、metadata 参数（--help 查看）")
        if not output:
            raise ValueError("analyze 需要输出 -o/--output（--help 查看）")
        if not sample_var:
            raise ValueError("analyze 需要 --sample-var（元数据中样本 ID 列名）")
        if not main_var:
            raise ValueError("analyze 需要 --main-var（主分组变量列名）")

        tmpdir = self.make_tmpdir("ancom_")
        params = Path(tmpdir) / "params.tsv"
        pairs = [
            ("feature_table", os.path.abspath(str(feature_table))),
            ("metadata", os.path.abspath(str(metadata))),
            ("output", os.path.abspath(str(output))),
            ("sample_var", str(sample_var)),
            ("main_var", str(main_var)),
        ]
        for key, default in (
            ("group_var", None),
            ("adj_formula", None),
            ("rand_formula", None),
            ("ancom_home", None),
        ):
            val = kw.get(key)
            if val:
                pairs.append((key, str(val)))
        pairs.append(("out_cut", str(0.05 if kw.get("out_cut") is None else kw["out_cut"])))
        pairs.append(("zero_cut", str(0.9 if kw.get("zero_cut") is None else kw["zero_cut"])))
        pairs.append(("lib_cut", str(int(0 if kw.get("lib_cut") is None else kw["lib_cut"]))))
        pairs.append(("neg_lb", "TRUE" if kw.get("neg_lb") else "FALSE"))
        pairs.append(("p_adj_method", str(kw.get("p_adj_method") or "BH")))
        pairs.append(("alpha", str(0.05 if kw.get("alpha") is None else kw["alpha"])))
        if kw.get("extra_args"):
            raise ValueError("analyze 不支持 extra_args（参数已结构化，如需扩展请改 run_ancom.R）")

        params.write_text("".join(f"{k}\t{v}\n" for k, v in pairs), encoding="utf-8")
        return [rscript, str(self._driver()), str(params)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ancom-skill",
        description="ANCOM native 技能驱动（Rscript 运行 run_ancom.R）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("analyze", help=SUBCOMMANDS["analyze"])
    pa.add_argument("feature_table", help="特征丰度表（Tab 分隔，首列特征 id，其余列样本）")
    pa.add_argument("metadata", help="样本元数据表（Tab 分隔，首列样本 id）")
    pa.add_argument("-o", "--output", required=True, help="差异丰度结果 CSV 输出路径")
    pa.add_argument("--sample-var", dest="sample_var", required=True,
                    help="元数据中样本 ID 列名（如 Sample.ID）")
    pa.add_argument("--main-var", dest="main_var", required=True,
                    help="主分组变量列名（分类变量，需恰为两组）")
    pa.add_argument("--group-var", dest="group_var",
                    help="结构零识别的分组列（纵向/多组场景）")
    pa.add_argument("--out-cut", dest="out_cut", type=float, default=0.05,
                    help="离群判定阈值（默认 0.05）")
    pa.add_argument("--zero-cut", dest="zero_cut", type=float, default=0.9,
                    help="零比例高于该值的特征剔除（默认 0.90）")
    pa.add_argument("--lib-cut", dest="lib_cut", type=int, default=0,
                    help="文库大小低于该值的样本剔除（默认 0）")
    pa.add_argument("--neg-lb", dest="neg_lb", action="store_true",
                    help="结构零判定同时使用渐近下界判据")
    pa.add_argument("--p-adj-method", dest="p_adj_method", default="BH",
                    help="多重比较校正方法（默认 BH）")
    pa.add_argument("--alpha", type=float, default=0.05, help="显著性水平（默认 0.05）")
    pa.add_argument("--adj-formula", dest="adj_formula", help="协变量校正公式字符串")
    pa.add_argument("--rand-formula", dest="rand_formula", help="随机效应公式（nlme::lme）")
    pa.add_argument("--ancom-home", dest="ancom_home",
                    help="ANCOM 源码目录（含 programs/ancom.R；缺省用 ANCOM_HOME / ~/software/ANCOM）")
    _add_runtime_opts(pa)
    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（ANCOM 单进程，仅接口保留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = AncomSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AncomSkill()
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
