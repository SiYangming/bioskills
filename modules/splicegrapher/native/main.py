#!/usr/bin/env python3
"""splicegrapher native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py build_classifiers -d gt,gc -a ag -l create_classifiers.log
   python main.py sam_filter filtered.sam classifiers.zip -o filtered.out.sam -v
   python main.py predict_graphs filtered.sam -v
   python main.py realignment_pipeline graphs/ -1 A.1.fastq -2 A.2.fastq
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（脚本来自 SpliceGrapher 0.2.7 官方 scripts/）：
  build_classifiers    build_classifiers.py -d gt,gc -a ag [-n N] [-l <log>]
  sam_filter           sam_filter.py <input.sam> <classifiers.zip> [-o <filtered.sam>] [-v]
  predict_graphs       predict_graphs.py <input.sam> [-o <outdir>] [-v]
  realignment_pipeline realignment_pipeline.py <graph_dir> -1 <fq1> -2 <fq2>
运行前需设置环境变量 SG_FASTA_REF（参考基因组 FASTA）与 SG_GENE_MODEL（基因模型 GFF3）。
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
    "build_classifiers": "训练剪接位点 SVM 分类器（build_classifiers.py -d gt,gc -a ag）",
    "sam_filter": "用分类器过滤比对（sam_filter.py <sam> <classifiers.zip> -o <out>）",
    "predict_graphs": "预测剪接图（predict_graphs.py <sam>）",
    "realignment_pipeline": "剪接图重比对（realignment_pipeline.py <graphs> -1 <fq1> -2 <fq2>）",
}

# 子命令 -> 官方 scripts/ 下的脚本名
SUBCOMMAND_BINARY = {
    "build_classifiers": "build_classifiers.py",
    "sam_filter": "sam_filter.py",
    "predict_graphs": "predict_graphs.py",
    "realignment_pipeline": "realignment_pipeline.py",
}


class SpliceGrapherSkill(base.SkillBase):
    software = "splicegrapher"
    binary = "build_classifiers.py"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析可执行脚本（测试可 monkeypatch 本方法）。"""
        name = name or self.binary
        path = which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行脚本 '{name}'，请先安装 SpliceGrapher（conda/容器/源码，见 README）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建对应 SpliceGrapher 脚本命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(SUBCOMMAND_BINARY[subcommand])
        cmd: list[str] = [binary]

        if subcommand == "build_classifiers":
            cmd += ["-d", str(kw.get("donors") or "gt,gc")]
            cmd += ["-a", str(kw.get("acceptors") or "ag")]
            if kw.get("num_examples") is not None:
                cmd += ["-n", str(kw["num_examples"])]
            if kw.get("logfile"):
                cmd += ["-l", str(kw["logfile"])]

        elif subcommand == "sam_filter":
            sam = kw.get("input") or kw.get("sam")
            classifiers = kw.get("classifiers") or kw.get("classifier")
            if not (sam and classifiers):
                raise ValueError("sam_filter 缺少必填参数：input(SAM) 与 classifiers(classifiers.zip)")
            cmd += [str(sam), str(classifiers)]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("verbose"):
                cmd.append("-v")

        elif subcommand == "predict_graphs":
            sam = kw.get("input") or kw.get("sam")
            if not sam:
                raise ValueError("predict_graphs 缺少必填参数 input(SAM)")
            cmd.append(str(sam))
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]
            if kw.get("verbose"):
                cmd.append("-v")

        elif subcommand == "realignment_pipeline":
            graph_dir = kw.get("input") or kw.get("graph_dir")
            fq1 = kw.get("fastq1")
            fq2 = kw.get("fastq2")
            if not (graph_dir and fq1 and fq2):
                raise ValueError("realignment_pipeline 缺少必填参数：input(剪接图目录) / -1 / -2")
            cmd += [str(graph_dir), "-1", str(fq1), "-2", str(fq2)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 注：SpliceGrapher 脚本无统一线程参数，--threads 仅用于调度（不注入命令行）
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
    p.add_argument("--threads", type=int, help="线程数（接口兼容；脚本无统一线程参数，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="splicegrapher-skill",
        description="splicegrapher native 技能驱动（可变剪接：分类器/过滤/剪接图/重比对）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # build_classifiers
    pc = sub.add_parser("build_classifiers", help=SUBCOMMANDS["build_classifiers"])
    pc.add_argument("-d", "--donors", help="供体剪接位点类型（默认 gt,gc）")
    pc.add_argument("-a", "--acceptors", help="受体剪接位点类型（默认 ag）")
    pc.add_argument("-n", "--num-examples", type=int, help="每个位点训练样本数（默认 2000）")
    pc.add_argument("-l", "--logfile", help="日志文件")
    pc.add_argument("--extra-args", help="透传脚本的额外参数")
    _add_runtime_opts(pc)

    # sam_filter
    ps = sub.add_parser("sam_filter", help=SUBCOMMANDS["sam_filter"])
    ps.add_argument("input", nargs="?", help="输入 SAM（别名 --sam）")
    ps.add_argument("classifiers", nargs="?", help="分类器压缩包 classifiers.zip")
    ps.add_argument("--sam", help="输入 SAM 的别名")
    ps.add_argument("-o", "--output", help="输出过滤后 SAM")
    ps.add_argument("-v", "--verbose", action="store_true", help="详细输出")
    ps.add_argument("--extra-args", help="透传脚本的额外参数")
    _add_runtime_opts(ps)

    # predict_graphs
    pp = sub.add_parser("predict_graphs", help=SUBCOMMANDS["predict_graphs"])
    pp.add_argument("input", nargs="?", help="输入 SAM（别名 --sam）")
    pp.add_argument("--sam", help="输入 SAM 的别名")
    pp.add_argument("-o", "--output", help="输出目录/前缀")
    pp.add_argument("-v", "--verbose", action="store_true", help="详细输出")
    pp.add_argument("--extra-args", help="透传脚本的额外参数")
    _add_runtime_opts(pp)

    # realignment_pipeline
    pr = sub.add_parser("realignment_pipeline", help=SUBCOMMANDS["realignment_pipeline"])
    pr.add_argument("input", nargs="?", help="剪接图目录（别名 --graph-dir）")
    pr.add_argument("--graph-dir", help="剪接图目录的别名")
    pr.add_argument("-1", "--fastq1", dest="fastq1", help="read1 FASTQ")
    pr.add_argument("-2", "--fastq2", dest="fastq2", help="read2 FASTQ")
    pr.add_argument("--extra-args", help="透传脚本的额外参数")
    _add_runtime_opts(pr)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:22s} {v}")
        return 0
    if "--schema" in args:
        skill = SpliceGrapherSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SpliceGrapherSkill()
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
