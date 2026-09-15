#!/usr/bin/env python3
"""emperor native 标准入口驱动（Emperor，微生物组 PCoA 交互式可视化）。

Emperor 以 Python 库形态分发，无独立命令行二进制（无 __main__.py / console_scripts；
`python -m emperor` 不是有效入口，2026-09 核实）。本驱动以 python3 运行同目录
run_emperor.py，调用 emperor.core.Emperor 把 ordination（PCoA 结果）+ 元数据渲染为交互式 HTML。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py plot ordination.txt sample-metadata.tsv -o emperor.html
   python main.py plot ordination.txt metadata.tsv -o emperor.html \
       --custom-axes DaysSinceExperimentStart --dimensions 3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

前置：python>=3.8 且已安装 emperor（pip install emperor==1.0.5 /
mamba create -n <env> -c conda-forge emperor=1.0.5），依赖 scikit-bio、pandas。
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
    "plot": "Emperor：ordination（PCoA/排序结果）+ 元数据 -> 交互式 3D HTML 可视化",
}


class EmperorSkill(base.SkillBase):
    software = "emperor"
    binary = "python3"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/emperor/meta.yaml（不在 native/ 下）
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _driver(self) -> Path:
        return _HERE / "run_emperor.py"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构建 `python3 run_emperor.py --ordination ... --metadata ... --output ...` 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        python = self._resolve_binary()
        # 解析线程（Emperor 为单进程渲染，无对应 flag，仅保证接口/优先级一致）
        self._effective_threads(subcommand, kw.get("threads"))

        ordination = kw.get("ordination")
        metadata = kw.get("metadata")
        output = kw.get("output")
        if not ordination:
            raise ValueError("plot 缺少必填参数 ordination（排序结果文件）")
        if not metadata:
            raise ValueError("plot 缺少必填参数 metadata（样本元数据表）")
        if not output:
            raise ValueError("plot 缺少必填参数 output（输出 HTML 路径）")

        cmd: list[str] = [python, str(self._driver())]
        cmd += ["--ordination", str(ordination)]
        cmd += ["--metadata", str(metadata)]
        cmd += ["--output", str(output)]

        axes = kw.get("custom_axes")
        if axes:
            if isinstance(axes, (list, tuple)):
                for ax in axes:
                    cmd += ["--custom-axis", str(ax)]
            else:
                for ax in str(axes).split(","):
                    if ax.strip():
                        cmd += ["--custom-axis", ax.strip()]
        if kw.get("dimensions") is not None:
            cmd += ["--dimensions", str(kw["dimensions"])]
        if kw.get("ignore_missing_samples"):
            cmd.append("--ignore-missing-samples")
        if kw.get("remote"):
            cmd.append("--remote")
        if kw.get("extra_args"):
            cmd += str(kw["extra_args"]).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="emperor-skill",
        description="emperor native 技能驱动（Python 驱动 emperor.core.Emperor 渲染 PCoA HTML）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pp = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    pp.add_argument("ordination", help="排序结果文件（skbio OrdinationResults 文本格式）")
    pp.add_argument("metadata", help="样本元数据表（Tab 分隔，首列样本 ID）")
    pp.add_argument("-o", "--output", required=True, help="输出 HTML 文件路径")
    pp.add_argument("--custom-axes", help="自定义轴元数据列（逗号分隔，可多次给出）")
    pp.add_argument("--dimensions", type=int, default=5, help="保留的排序维度数（默认 5）")
    pp.add_argument("--ignore-missing-samples", action="store_true",
                    help="缺元数据的样本改为填充占位值（默认报错）")
    pp.add_argument("--remote", action="store_true",
                    help="使用远程 CDN 资源（默认本地随包资源）")
    pp.add_argument("--extra-args", help="透传给 run_emperor.py 的额外参数")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（Emperor 单进程，仅接口保留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = EmperorSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = EmperorSkill()
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
