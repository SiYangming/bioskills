#!/usr/bin/env python3
"""wtdbg2 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble subreads.fasta -o dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
   python main.py cns dbg.ctg.lay.gz -fo dbg.raw.fa -t 8 -j 1000
   python main.py polish dbg.raw.fa -i dbg.bam -fo dbg.cns.fa -t 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（文档 04.md 第 1498-1508 行）：
  assemble  wtdbg2 -i <reads> -o <prefix> -t N -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
  cns       wtpoa-cns -t N -j 1000 -i <prefix>.ctg.lay.gz -fo <out.fa>
  polish    wtpoa-cns -t N [-x sam-sr] -d <draft.fa> -i <aln|-> -fo <out.fa>
二进制惰性解析：assemble→wtdbg2，cns/polish→wtpoa-cns。
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus（注入 -t）。
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
    "assemble": "建图（wtdbg2 -i <reads> -o <prefix> -p 21 -S 4 -s 0.05 -g <size> ...）",
    "cns": "取一致性序列（wtpoa-cns -i <prefix>.ctg.lay.gz -fo <out.fa>）",
    "polish": "用比对结果打磨草图（wtpoa-cns -d <draft> -i <aln|-> -fo <out.fa> [-x sam-sr]）",
}

# 子命令 -> 二进制名
SUBCOMMAND_BINARY = {"assemble": "wtdbg2", "cns": "wtpoa-cns", "polish": "wtpoa-cns"}


class Wtdbg2Skill(base.SkillBase):
    software = "wtdbg2"
    binary = "wtdbg2"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析二进制（可被测试 monkeypatch）；name 缺省时用 self.binary。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 wtdbg2 / wtpoa-cns 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(SUBCOMMAND_BINARY[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd: list[str] = [binary]

        if subcommand == "assemble":
            reads = kw.get("reads") or kw.get("input")
            if not reads:
                raise ValueError("assemble 缺少必填参数 reads（-i 输入长读）")
            output = kw.get("output")
            if not output:
                raise ValueError("assemble 缺少必填参数 output（-o 输出前缀）")
            cmd += ["-i", str(reads), "-o", str(output), "-t", str(threads)]
            if kw.get("kmer") is not None:
                cmd += ["-p", str(kw["kmer"])]
            if kw.get("sampling") is not None:
                cmd += ["-S", str(kw["sampling"])]
            if kw.get("error_rate") is not None:
                cmd += ["-s", str(kw["error_rate"])]
            if kw.get("genome_size") is not None:
                cmd += ["-g", str(kw["genome_size"])]
            if kw.get("min_read_len") is not None:
                cmd += ["-L", str(kw["min_read_len"])]
            if kw.get("min_overlap_len") is not None:
                cmd += ["-l", str(kw["min_overlap_len"])]

        elif subcommand == "cns":
            layout = kw.get("layout") or kw.get("input")
            if not layout:
                raise ValueError("cns 缺少必填参数 layout（-i <prefix>.ctg.lay.gz）")
            fasta_out = kw.get("fasta_out") or kw.get("output")
            if not fasta_out:
                raise ValueError("cns 缺少必填参数 fasta_out（-fo 输出 FASTA）")
            cmd += ["-t", str(threads)]
            if kw.get("min_len") is not None:
                cmd += ["-j", str(kw["min_len"])]
            cmd += ["-i", str(layout), "-fo", str(fasta_out)]

        elif subcommand == "polish":
            draft = kw.get("draft")
            if not draft:
                raise ValueError("polish 缺少必填参数 draft（-d 草图 FASTA）")
            fasta_out = kw.get("fasta_out") or kw.get("output")
            if not fasta_out:
                raise ValueError("polish 缺少必填参数 fasta_out（-fo 输出 FASTA）")
            cmd += ["-t", str(threads)]
            if kw.get("preset"):
                cmd += ["-x", str(kw["preset"])]
            cmd += ["-d", str(draft)]
            cmd += ["-i", str(kw.get("alignment") or "-")]
            cmd += ["-fo", str(fasta_out)]

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
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 -t）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wtdbg2-skill",
        description="wtdbg2 native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # assemble
    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("reads", nargs="?", help="输入长读序列（FASTA/FASTQ）")
    pa.add_argument("-o", "--output", help="输出前缀（生成 <prefix>.ctg.lay.gz 等）")
    pa.add_argument("-p", "--kmer", type=int, default=21, help="k-mer 长度（默认 21）")
    pa.add_argument("-S", "--sampling", type=int, help="采样率（文档示例 4）")
    pa.add_argument("-s", "--error-rate", type=float, help="错误率（文档示例 0.05）")
    pa.add_argument("-g", "--genome-size", help="估计基因组大小（如 8m）")
    pa.add_argument("-L", "--min-read-len", type=int, help="最小 read 长度（文档示例 2000）")
    pa.add_argument("-l", "--min-overlap-len", type=int, help="最小重叠长度（文档示例 1000）")
    pa.add_argument("--extra-args", help="透传给 wtdbg2 的额外参数")
    _add_runtime_opts(pa)

    # cns
    pc = sub.add_parser("cns", help=SUBCOMMANDS["cns"])
    pc.add_argument("layout", nargs="?", help="<prefix>.ctg.lay.gz（wtdbg2 产出）")
    pc.add_argument("-fo", "--fasta-out", dest="fasta_out", help="输出一致性 FASTA")
    pc.add_argument("-j", "--min-len", type=int, help="最小匹配/重叠长度阈值（文档示例 1000）")
    pc.add_argument("--extra-args", help="透传给 wtpoa-cns 的额外参数")
    _add_runtime_opts(pc)

    # polish
    pp = sub.add_parser("polish", help=SUBCOMMANDS["polish"])
    pp.add_argument("-d", "--draft", help="待打磨草图 FASTA")
    pp.add_argument("-i", "--alignment", help="比对结果（BAM/SAM，或 - 读 stdin）")
    pp.add_argument("-fo", "--fasta-out", dest="fasta_out", help="输出打磨后 FASTA")
    pp.add_argument("-x", "--preset", help="比对预设（如 sam-sr 短读打磨）")
    pp.add_argument("--extra-args", help="透传给 wtpoa-cns 的额外参数")
    _add_runtime_opts(pp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Wtdbg2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Wtdbg2Skill()
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
