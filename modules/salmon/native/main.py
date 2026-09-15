#!/usr/bin/env python3
"""salmon native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py index -t Trinity.fasta -i salmon_index -k 31
   python main.py quant -i salmon_index -1 A1.1.fastq -2 A1.2.fastq -o salmon_out/A1 --threads 8
   python main.py quantmerge --quants salmon_out/A1 salmon_out/A2 -o merged/quant
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  index       salmon index -t <transcripts.fa> -i <index> --type quasi -k <k> -p N
  quant       salmon quant -i <index> -l A (-1 r1 -2 r2 | -r reads) -p N --validateMappings -o <out>
  quantmerge  salmon quantmerge --quants <dir...> -o <out>
所有子命令自动注入线程与临时目录优化。
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
    "index": "构建转录组 quasi-mapping 索引",
    "quant": "转录本定量（准映射，支持双端/单端）",
    "quantmerge": "合并多样本定量结果（quantmerge）",
}

# 支持线程注入的子命令（salmon index/quant 用 -p）
SUPPORTS_THREADS = {"index", "quant"}


class SalmonSkill(base.SkillBase):
    software = "salmon"
    binary = "salmon"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 salmon 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "index":
            transcripts = kw.get("transcripts") or kw.get("input")
            if not transcripts:
                raise ValueError("index 缺少必填参数 transcripts（转录本 FASTA，-t）")
            index = kw.get("index")
            if not index:
                raise ValueError("index 缺少必填参数 index（输出索引路径，-i）")
            cmd: list[str] = [binary, "index", "-t", str(transcripts), "-i", str(index)]
            cmd += ["--type", str(kw.get("type") or "quasi")]
            cmd += ["-k", str(kw.get("kmer") or 31)]
            cmd += ["-p", str(threads)]
            if kw.get("keep_duplicates"):
                cmd.append("--keepDuplicates")

        elif subcommand == "quant":
            index = kw.get("index")
            if not index:
                raise ValueError("quant 缺少必填参数 index（-i）")
            cmd = [binary, "quant", "-i", str(index)]
            cmd += ["-l", str(kw.get("libtype") or "A")]
            if kw.get("left"):
                cmd += ["-1", str(kw["left"])]
                if kw.get("right"):
                    cmd += ["-2", str(kw["right"])]
            elif kw.get("reads"):
                cmd += ["-r", str(kw["reads"])]
            else:
                raise ValueError("quant 需要双端（--left/--right，-1/-2）或单端（--reads，-r）输入")
            cmd += ["-p", str(threads)]
            if kw.get("validate_mappings", True):
                cmd.append("--validateMappings")
            if kw.get("gc_bias"):
                cmd.append("--gcBias")
            if kw.get("seq_bias"):
                cmd.append("--seqBias")
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        else:  # quantmerge
            quants = kw.get("quants") or []
            if not quants:
                raise ValueError("quantmerge 缺少必填参数 quants（定量结果目录列表）")
            cmd = [binary, "quantmerge"]
            cmd += ["--quants"] + [str(q) for q in quants]
            if kw.get("names"):
                cmd += ["--names", str(kw["names"])]
            if kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="salmon-skill",
        description="salmon native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("-t", "--transcripts", required=True, help="转录本 FASTA")
    pi.add_argument("-i", "--index", required=True, help="输出索引路径")
    pi.add_argument("--type", default="quasi", choices=["quasi", "fmd"], help="索引类型（默认 quasi）")
    pi.add_argument("-k", "--kmer", type=int, default=31, help="k-mer 长度（默认 31）")
    pi.add_argument("--keep-duplicates", action="store_true", help="保留重复序列（--keepDuplicates）")
    pi.add_argument("--extra-args", help="透传给 salmon 的额外参数")
    _add_runtime_opts(pi)

    # quant
    pq = sub.add_parser("quant", help=SUBCOMMANDS["quant"])
    pq.add_argument("-i", "--index", required=True, help="salmon 索引目录")
    pq.add_argument("-1", "--left", help="左端 fastq（双端）")
    pq.add_argument("-2", "--right", help="右端 fastq（双端）")
    pq.add_argument("-r", "--reads", help="单端 fastq")
    pq.add_argument("-l", "--libtype", default="A", help="文库类型（默认 A=自动）")
    pq.add_argument("-o", "--output", help="输出目录")
    pq.add_argument("--gc-bias", action="store_true", help="开启 --gcBias 校正")
    pq.add_argument("--seq-bias", action="store_true", help="开启 --seqBias 校正")
    pq.add_argument("--no-validate-mappings", dest="validate_mappings", action="store_false",
                    help="关闭 --validateMappings")
    pq.add_argument("--extra-args", help="透传给 salmon 的额外参数")
    _add_runtime_opts(pq)

    # quantmerge
    pm = sub.add_parser("quantmerge", help=SUBCOMMANDS["quantmerge"])
    pm.add_argument("quants", nargs="+", help="待合并的定量结果目录列表")
    pm.add_argument("-o", "--output", help="合并输出前缀/文件")
    pm.add_argument("--names", help="样本名（逗号或空格分隔）")
    pm.add_argument("--extra-args", help="透传给 salmon 的额外参数")
    _add_runtime_opts(pm)

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
        skill = SalmonSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SalmonSkill()
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
