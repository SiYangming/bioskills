#!/usr/bin/env python3
"""DBG2OLC native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py sparseassembler illumina.1.fastq illumina.2.fastq --k 31 --g 15 --gs 1000000
   python main.py dbg2olc subreads.fasta --contigs Contigs.txt --adaptive-th 0.015 --kmer-cov-th 5 --min-overlap 50
   python main.py sparc --backbone backbone_raw.fasta --info DBG2OLC_Consensus_info.txt --ctg-pb ctg_pb.fasta --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐文档 04.md「16. DBG2OLC 安装与使用」）：
  sparseassembler  SparseAssembler LD <ld> k <k> g <g> NodeCovTh <n> EdgeCovTh <e> GS <gs> f <reads...>
  dbg2olc          DBG2OLC LD <ld> k <k> AdaptiveTh <th> KmerCovTh <n> MinOverlap <l> RemoveChimera <c> Contigs <contigs> f <reads...>
  sparc            split_and_run_sparc.sh <backbone> <info> <ctg_pb> <outdir> <cores>
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
    "sparseassembler": "SparseAssembler 短读 de Bruijn 图组装 -> Contigs.txt",
    "dbg2olc": "DBG2OLC 长读 layout 到 contigs -> backbone_raw.fasta + DBG2OLC_Consensus_info.txt",
    "sparc": "split_and_run_sparc.sh（+ blasr）consensus -> final_assembly.fasta",
}

# 子命令 -> 默认官方可执行名
BINARY_BY_SUBCOMMAND = {
    "sparseassembler": "SparseAssembler",
    "dbg2olc": "DBG2OLC",
    "sparc": "split_and_run_sparc.sh",
}


class Dbg2olcSkill(base.SkillBase):
    software = "dbg2olc"
    binary = "DBG2OLC"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令惰性解析官方可执行文件（DBG2OLC / SparseAssembler / split_and_run_sparc.sh）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 DBG2OLC。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 DBG2OLC 三段链路命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = []

        if subcommand == "sparseassembler":
            reads = _as_list(kw.get("reads"))
            if not reads:
                raise ValueError("sparseassembler 缺少必填参数 reads（短读 FASTQ/FASTA）")
            cmd = [
                self._resolve_binary(BINARY_BY_SUBCOMMAND[subcommand]),
                "LD", str(kw.get("ld", 0)),
                "k", str(kw.get("k", 31)),
                "g", str(kw.get("g", 15)),
                "NodeCovTh", str(kw.get("nodecov", 1)),
                "EdgeCovTh", str(kw.get("edgecov", 0)),
                "GS", str(kw.get("gs", 1000000)),
            ]
            for r in reads:
                cmd += ["f", str(r)]

        elif subcommand == "dbg2olc":
            reads = _as_list(kw.get("reads"))
            contigs = kw.get("contigs")
            if not contigs:
                raise ValueError("dbg2olc 缺少必填参数 contigs（SparseAssembler 产出的 Contigs.txt）")
            cmd = [
                self._resolve_binary(BINARY_BY_SUBCOMMAND[subcommand]),
                "LD", str(kw.get("ld", 0)),
                "k", str(kw.get("k", 17)),
                "AdaptiveTh", str(kw.get("adaptive_th", 0.001)),
                "KmerCovTh", str(kw.get("kmer_cov_th", 2)),
                "MinOverlap", str(kw.get("min_overlap", 20)),
                "RemoveChimera", str(kw.get("remove_chimera", 1)),
                "Contigs", str(contigs),
            ]
            for r in reads:
                cmd += ["f", str(r)]

        elif subcommand == "sparc":
            backbone, info, ctg_pb = kw.get("backbone"), kw.get("info"), kw.get("ctg_pb")
            if not (backbone and info and ctg_pb):
                raise ValueError("sparc 需要 --backbone / --info / --ctg-pb 三个输入")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd = [
                self._resolve_binary(BINARY_BY_SUBCOMMAND[subcommand]),
                str(backbone), str(info), str(ctg_pb),
                str(kw.get("outdir") or "."),
                str(threads),
            ]

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
        prog="dbg2olc-skill",
        description="DBG2OLC native 技能驱动（短读 DBG 组装 -> 长读 layout -> Sparc consensus）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # sparseassembler
    ps = sub.add_parser("sparseassembler", help=SUBCOMMANDS["sparseassembler"])
    ps.add_argument("reads", nargs="+", help="短读 FASTQ/FASTA（可多个，自动前置 f）")
    ps.add_argument("--ld", type=int, default=0, help="LD 开关（0=初始，1=加载已有结果；默认 0）")
    ps.add_argument("--k", type=int, default=31, help="k-mer 长度（默认 31）")
    ps.add_argument("--g", type=int, default=15, help="g 参数（默认 15）")
    ps.add_argument("--nodecov", type=int, default=1, help="NodeCovTh 节点覆盖度阈值（默认 1）")
    ps.add_argument("--edgecov", type=int, default=0, help="EdgeCovTh 边覆盖度阈值（默认 0）")
    ps.add_argument("--gs", type=int, default=1000000, help="GS 基因组大小估计（默认 1000000）")
    ps.add_argument("--extra-args", help="透传给 SparseAssembler 的额外参数")
    _add_runtime_opts(ps)

    # dbg2olc
    pd = sub.add_parser("dbg2olc", help=SUBCOMMANDS["dbg2olc"])
    pd.add_argument("reads", nargs="*", help="长读 FASTA（subreads.fasta，可多个，自动前置 f）")
    pd.add_argument("--contigs", required=True, help="SparseAssembler 产出的 Contigs.txt")
    pd.add_argument("--ld", type=int, default=0, help="LD 开关（默认 0）")
    pd.add_argument("--k", type=int, default=17, help="比对 k-mer 长度（默认 17）")
    pd.add_argument("--adaptive-th", type=float, default=0.001, help="AdaptiveTh 自适应阈值（默认 0.001）")
    pd.add_argument("--kmer-cov-th", type=int, default=2, help="KmerCovTh k-mer 覆盖度阈值（默认 2）")
    pd.add_argument("--min-overlap", type=int, default=20, help="MinOverlap 最小重叠长度（默认 20）")
    pd.add_argument("--remove-chimera", type=int, default=1, help="RemoveChimera 去嵌合（默认 1）")
    pd.add_argument("--extra-args", help="透传给 DBG2OLC 的额外参数")
    _add_runtime_opts(pd)

    # sparc
    pp = sub.add_parser("sparc", help=SUBCOMMANDS["sparc"])
    pp.add_argument("--backbone", required=True, help="backbone_raw.fasta")
    pp.add_argument("--info", required=True, help="DBG2OLC_Consensus_info.txt")
    pp.add_argument("--ctg-pb", dest="ctg_pb", required=True, help="contigs + 长读合并文件 ctg_pb.fasta")
    pp.add_argument("--outdir", default=".", help="consensus 输出目录（默认 .）")
    pp.add_argument("--extra-args", help="透传给 split_and_run_sparc.sh 的额外参数")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（sparc 生效）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = Dbg2olcSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Dbg2olcSkill()
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
