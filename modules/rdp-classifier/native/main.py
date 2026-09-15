#!/usr/bin/env python3
"""rdp-classifier native 标准入口驱动（RDP Classifier，Java 工具）。

RDP Classifier 以 Java 分发：bioconda 提供 rdp_classifier 包装脚本（从命令行提取
-Xmx/-D/-XX 作为 JVM 参数后调用 dist/classifier.jar）。本驱动把 classify 参数组装为
`rdp_classifier [-Xmx...] classify -t <train_propfile> -o <out> -f <format> -c <conf> ... <query.fna>`。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py classify rep_set.fna -o rdp_assigned_taxonomy.txt --conf 0.8 --threads 8
   python main.py classify rep_seqs.fna -t rRNAClassifier.properties -o taxonomy.txt -f allrank
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

JVM 参数：optimization.env_vars.JAVA_OPTS（默认 -Xmx6g）中的 -Xm*/-D*/-XX* token 会在
classify 之前透传给包装脚本（与 RDP 包装脚本的参数提取逻辑一致）。
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
    "classify": "RDP 朴素贝叶斯分类器：16S rRNA 序列 FASTA -> 界/门/纲/目/科/属 分类注释",
}

# RDP classifier 支持的输出格式（CmdOptions.FORMAT_DESC）
FORMATS = ["allrank", "fixrank", "biom", "filterbyconf", "db"]


class RdpClassifierSkill(base.SkillBase):
    software = "rdp-classifier"
    binary = "rdp_classifier"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/rdp-classifier/meta.yaml（不在 native/ 下）
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        注：RDP Classifier 是单线程 Java 程序，无 -p/--threads 参数；此处保留统一线程解析
        仅为 meta 一致性与接口对齐（--threads 仍被接受）。
        """
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _java_opts(self) -> list[str]:
        """从 JAVA_OPTS 提取 JVM 参数（-Xm*/-D*/-XX*），与 RDP 包装脚本的提取规则一致。"""
        raw = (self.env_vars or {}).get("JAVA_OPTS", "")
        return [t for t in shlex.split(raw) if t.startswith(("-Xm", "-D", "-XX"))]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构建 `rdp_classifier [JVM opts] classify [options] <query>` 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_binary()
        # 解析线程（RDP 单线程无对应 flag，仅保证接口/优先级一致）
        self._effective_threads(subcommand, kw.get("threads"))

        cmd: list[str] = [binary] + self._java_opts() + ["classify"]

        train_propfile = kw.get("train_propfile")
        if train_propfile:
            cmd += ["-t", str(train_propfile)]

        output = kw.get("output")
        if output:
            cmd += ["-o", str(output)]

        fmt = kw.get("format") or "fixrank"
        cmd += ["-f", str(fmt)]

        # conf 缺省对齐 meta 默认 0.8（RDP Classifier 自身默认亦为 0.8）
        conf = kw.get("conf")
        cmd += ["-c", str(0.8 if conf is None else conf)]
        if kw.get("gene"):
            cmd += ["-g", str(kw["gene"])]
        if kw.get("min_words") is not None:
            cmd += ["-w", str(kw["min_words"])]
        if kw.get("rank"):
            cmd += ["-r", str(kw["rank"])]
        if kw.get("taxon"):
            cmd += ["-n", str(kw["taxon"])]
        if kw.get("bootstrap_outfile"):
            cmd += ["-b", str(kw["bootstrap_outfile"])]
        if kw.get("shortseq_outfile"):
            cmd += ["-s", str(kw["shortseq_outfile"])]

        # 高级透传（慎用）：置于查询序列之前
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        query = kw.get("query") or kw.get("input")
        if not query:
            raise ValueError("classify 缺少必填参数 query（输入 FASTA 序列文件）")
        cmd.append(str(query))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="rdp-classifier-skill",
        description="rdp-classifier native 技能驱动（RDP Classifier，JAVA_OPTS 透传）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("classify", help=SUBCOMMANDS["classify"])
    pc.add_argument("query", nargs="?", help="待分类查询序列 FASTA（别名 --query）")
    pc.add_argument("--query", help="查询序列 FASTA 的别名")
    pc.add_argument("-t", "--train-propfile", help="训练集属性文件（rRNAClassifier.properties）")
    pc.add_argument("-o", "--output", help="分类结果输出文件")
    pc.add_argument("-f", "--format", choices=FORMATS, default="fixrank", help="输出格式（默认 fixrank）")
    pc.add_argument("-c", "--conf", type=float, default=0.8, help="置信度阈值 [0,1]（默认 0.8）")
    pc.add_argument("-g", "--gene", help="指定基因（如 16srrna）")
    pc.add_argument("-w", "--min-words", type=int, dest="min_words", help="每次 bootstrap 的最小词数")
    pc.add_argument("-r", "--rank", help="只输出到指定分类水平（如 genus）")
    pc.add_argument("-n", "--taxon", help="仅统计属于指定 taxon 的序列分配")
    pc.add_argument("-b", "--bootstrap-outfile", dest="bootstrap_outfile", help="bootstrap 计数输出文件")
    pc.add_argument("-s", "--shortseq-outfile", dest="shortseq_outfile", help="过短序列名输出文件")
    pc.add_argument("--extra-args", help="透传给 classifier.jar 的额外参数")
    _add_runtime_opts(pc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（RDP 单线程，仅接口保留）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = RdpClassifierSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RdpClassifierSkill()
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
