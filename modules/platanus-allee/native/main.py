#!/usr/bin/env python3
"""Platanus-allee native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble -t 8 -f illumina.1.fastq illumina.2.fastq
   python main.py phase -t 8 -c out_contig.fa out_junctionKmer.fa -IP1 illumina.1.fastq illumina.2.fastq -p subreads.fasta
   python main.py consensus -t 8 -c out_primaryBubble.fa out_nonBubbleHomoCandidate.fa -IP1 illumina.1.fastq illumina.2.fastq -p subreads.fasta
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐官方流程）：
  assemble   platanus_allee assemble -t N [-o out] -f <reads...> [-k 32] [-m 16] -tmp <dir>
  phase      platanus_allee phase -t N -c <contigs...> [-IP1 FWD REV] [-p <long reads...>] [-x <linked reads...>] [-o out] [-i 2] -tmp <dir>
  consensus  platanus_allee consensus -t N -c <contigs...> [-IP1 FWD REV] [-p <long reads...>] [-o out] -tmp <dir>
所有子命令自动注入线程（-t）与临时目录（-tmp）。
二进制惰性解析：测试通过 monkeypatch _resolve_binary 验证 argv 构造，不依赖工具已安装。
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
    "assemble": "Illumina 短读 contig 组装 -> <PREFIX>_contig.fa / _junctionKmer.fa",
    "phase": "结合长读/连锁读做单倍型 phasing -> <PREFIX>_allPhaseBlock.fa",
    "consensus": "拟单倍体 consensus 构建 -> <PREFIX>_consensusScaffold.fa",
}


class PlatanusAleeSkill(base.SkillBase):
    software = "platanus-allee"
    binary = "platanus_allee"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 platanus_allee 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))
        tmpdir = kw.get("tmpdir") or self.tmpdir

        cmd: list[str] = [binary, subcommand, "-t", str(threads)]

        if subcommand == "assemble":
            reads = _as_list(kw.get("reads"))
            if not reads:
                raise ValueError("assemble 缺少必填参数 reads（Illumina 双端 read 文件）")
            cmd += ["-f"] + [str(r) for r in reads]
            cmd += ["-o", str(kw.get("output") or "out")]
            if kw.get("k") is not None:
                cmd += ["-k", str(kw["k"])]
            if kw.get("mem_gb") is not None:
                cmd += ["-m", str(kw["mem_gb"])]

        elif subcommand in ("phase", "consensus"):
            contigs = _as_list(kw.get("contigs"))
            if not contigs:
                raise ValueError(f"{subcommand} 缺少必填参数 contigs（-c，FASTA）")
            cmd += ["-c"] + [str(c) for c in contigs]
            ip1 = _as_list(kw.get("ip1"))
            if ip1:
                cmd += ["-IP1"] + [str(x) for x in ip1]
            long_reads = _as_list(kw.get("long_reads"))
            if long_reads:
                cmd += ["-p"] + [str(x) for x in long_reads]
            linked = _as_list(kw.get("linked_reads"))
            if linked:
                cmd += ["-x"] + [str(x) for x in linked]
            cmd += ["-o", str(kw.get("output") or kw.get("out_prefix") or "out")]
            if kw.get("mapper"):
                cmd += ["-mapper", str(kw["mapper"])]
            if kw.get("minimap2_sensitive"):
                cmd += ["-minimap2_sensitive"]
            if subcommand == "phase" and kw.get("iterations") is not None:
                cmd += ["-i", str(kw["iterations"])]
            if kw.get("min_links") is not None:
                cmd += ["-l", str(kw["min_links"])]

        cmd += ["-tmp", str(tmpdir)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 由 main() 统一处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


def _as_list(value) -> list:
    """把 str / list / None 规范成列表（便于测试与 CLI 两种入口）。"""
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="platanus-allee-skill",
        description="Platanus-allee native 技能驱动（assemble -> phase -> consensus）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # assemble
    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("-f", "--reads", nargs="+", required=True, help="Illumina 双端 read 文件（可多个）")
    pa.add_argument("-o", "--output", help="输出前缀（默认 out）")
    pa.add_argument("-k", type=int, help="初始 k-mer 长度（默认 32）")
    pa.add_argument("-m", "--mem-gb", dest="mem_gb", type=int, help="k-mer 分布内存上限 GB（默认 16）")
    pa.add_argument("--extra-args", help="透传给 platanus_allee 的额外参数")
    _add_runtime_opts(pa)

    # phase / consensus 共用选项构造
    for name in ("phase", "consensus"):
        pp = sub.add_parser(name, help=SUBCOMMANDS[name])
        pp.add_argument("-c", "--contigs", nargs="+", required=True, help="contig/scaffold FASTA（可多个）")
        pp.add_argument("-IP1", "--ip1", nargs="+", help="inward-pair 文库（separate FWD REV）")
        pp.add_argument("-p", "--long-reads", dest="long_reads", nargs="+", help="长读文件（PacBio/ONT，需 minimap2）")
        pp.add_argument("-x", "--linked-reads", dest="linked_reads", nargs="+", help="10X linked-reads（barcoded fastq）")
        pp.add_argument("-o", "--output", help="输出前缀（默认 out，不得含 /）")
        pp.add_argument("-mapper", "--mapper", help="minimap2 可执行文件路径")
        pp.add_argument("-minimap2_sensitive", "--minimap2-sensitive", dest="minimap2_sensitive",
                        action="store_true", help="minimap2 敏感模式")
        pp.add_argument("-l", "--min-links", dest="min_links", type=int, help="scaffold 最小连接数（默认 3）")
        if name == "phase":
            pp.add_argument("-i", "--iterations", type=int, help="迭代次数（默认 2）")
        pp.add_argument("--extra-args", help="透传给 platanus_allee 的额外参数")
        _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（-t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（-tmp）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = PlatanusAleeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PlatanusAleeSkill()

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads
    kw["tmpdir"] = ns.tmpdir

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
