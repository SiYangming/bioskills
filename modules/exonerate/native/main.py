#!/usr/bin/env python3
"""exonerate native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align --model protein2genome --showtargetgff yes homolog.fasta genome.fasta -o exonerate.gff
   python main.py parallel --coverage_ratio 0.4 --evalue 1e-9 --threads 8 homolog.fasta genome.fasta
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐教学文档 docs/10.md 第四节）：
  align     exonerate --model <m> --showtargetgff yes [--bestn N] [--percent P] [--score S] <query> <target>
  parallel  exonerate_parallel.pl --cpu N [--coverage_ratio R] [--evalue E] <protein.fasta> <genome.fasta>
exonerate 本身把结果写到 stdout；align 子命令的 stdout 由本驱动在给出 --output 时落盘。
"""

from __future__ import annotations

import argparse
import json
import shutil
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
    "align": "exonerate 单次比对（--model protein2genome --showtargetgff yes <query> <target>，命中输出 GFF）",
    "parallel": "exonerate_parallel.pl 全基因组并行比对封装（--cpu/--coverage_ratio/--evalue）",
}

# 子命令 -> 实际可执行文件名
BINARY_FOR = {
    "align": "exonerate",
    "parallel": "exonerate_parallel.pl",
}


class ExonerateSkill(base.SkillBase):
    software = "exonerate"
    binary = "exonerate"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式：软件级 meta.yaml 位于 modules/exonerate/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（exonerate / exonerate_parallel.pl），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda exonerate=2.2.0 / 官方预编译二进制 exonerate-2.2.0-x86_64.tar.gz）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 exonerate 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "align":
            binary = self._resolve_tool(BINARY_FOR["align"])
            query = kw.get("query")
            target = kw.get("target")
            if not query:
                raise ValueError("align 缺少必填参数 query（查询蛋白 FASTA）")
            if not target:
                raise ValueError("align 缺少必填参数 target（目标基因组 FASTA）")
            cmd: list[str] = [binary]
            model = kw.get("model")
            if model:
                cmd += ["--model", str(model)]
            # --showtargetgff yes：命中以 GFF 形式写入 stdout（教学文档推荐用法）
            showgff = kw.get("showtargetgff")
            if showgff is not None:
                cmd += ["--showtargetgff", str(showgff)]
            if kw.get("bestn") is not None:
                cmd += ["--bestn", str(kw["bestn"])]
            if kw.get("percent") is not None:
                cmd += ["--percent", str(kw["percent"])]
            if kw.get("score") is not None:
                cmd += ["--score", str(kw["score"])]
            # 官方用法：exonerate [options] <query> <target>
            cmd += [str(query), str(target)]

        else:  # parallel
            binary = self._resolve_tool(BINARY_FOR["parallel"])
            query = kw.get("query")
            target = kw.get("target")
            if not query:
                raise ValueError("parallel 缺少必填参数 query（同源蛋白 FASTA）")
            if not target:
                raise ValueError("parallel 缺少必填参数 target（基因组 FASTA）")
            cmd = [binary, "--cpu", str(threads)]
            if kw.get("coverage_ratio") is not None:
                cmd += ["--coverage_ratio", str(kw["coverage_ratio"])]
            if kw.get("evalue") is not None:
                cmd += ["--evalue", str(kw["evalue"])]
            # 官方用法：exonerate_parallel.pl [options] <protein.fasta> <genome.fasta>
            cmd += [str(query), str(target)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="exonerate-skill",
        description="exonerate native 技能驱动（自动线程/临时目录优化；同源序列比对基因预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align [options] <query> <target>
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("query", nargs="?", help="查询序列（蛋白 FASTA；别名 --query）")
    pa.add_argument("--query", dest="query_opt", help="查询序列的别名")
    pa.add_argument("target", nargs="?", help="目标序列（基因组 FASTA；别名 --target）")
    pa.add_argument("--target", dest="target_opt", help="目标序列的别名")
    pa.add_argument("--model", default="protein2genome", help="比对模型（默认 protein2genome）")
    pa.add_argument("--showtargetgff", default="yes", help="输出目标 GFF（yes/no，默认 yes）")
    pa.add_argument("--bestn", type=int, help="仅报告最佳 n 个比对结果")
    pa.add_argument("--percent", type=int, help="最小相似性百分比")
    pa.add_argument("--score", type=int, help="最小得分阈值")
    pa.add_argument("-o", "--output", help="输出文件（exonerate 写 stdout，驱动捕获落盘）")
    pa.add_argument("--extra-args", dest="extra_args", help="透传给 exonerate 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pa)

    # parallel [options] <query> <target>
    pp = sub.add_parser("parallel", help=SUBCOMMANDS["parallel"])
    pp.add_argument("query", nargs="?", help="同源蛋白 FASTA（别名 --query）")
    pp.add_argument("--query", dest="query_opt", help="同源蛋白 FASTA 的别名")
    pp.add_argument("target", nargs="?", help="基因组 FASTA（别名 --target）")
    pp.add_argument("--target", dest="target_opt", help="基因组 FASTA 的别名")
    pp.add_argument("--coverage_ratio", type=float, help="覆盖度阈值（教学示例 0.4）")
    pp.add_argument("--evalue", help="E-value 阈值（教学示例 1e-9）")
    pp.add_argument("--extra-args", dest="extra_args", help="透传给 exonerate_parallel.pl 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（parallel 注入 --cpu N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = ExonerateSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ExonerateSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    # 位置参数与 --query/--target 别名归一
    kw["query"] = kw.get("query") or kw.get("query_opt")
    kw["target"] = kw.get("target") or kw.get("target_opt")
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # align：exonerate 写 stdout，给 --output 时落盘
    if ns.subcommand == "align" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stdout and not getattr(ns, "output", None):
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
