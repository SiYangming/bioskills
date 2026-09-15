#!/usr/bin/env python3
"""braker native 标准入口驱动。

BRAKER2（Gaius-Augustus/BRAKER）基因预测流水线的自包含驱动，覆盖 3 个子命令：
  run          braker.pl --species=... --genome=... --bam=... [--prot_seq=...] --cores N [--etpmode --softmasking]
  run_rnaseq   braker.pl --species=... --genome=... --bam=... --cores N [--softmasking]   （BRAKER1 模式，仅 RNA-seq）
  gtf2gff3     gtf2gff3.pl <braker.gtf>            （stdout -> --output，GFF3）

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run --genome genome.softmask.fasta --bam rnaseq.sort.bam \
       --prot_seq homolog.fasta --species my_species --cores 8 --etpmode --softmasking
   python main.py gtf2gff3 braker.gtf -o braker.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

依赖：AUGUSTUS / GeneMark-ES/ET / ProtHint / GenomeThreader(gth) / samtools / bamtools /
ncbi-rmblast / diamond / PASA；GeneMark 需 ~/.gm_key，并设置 AUGUSTUS_CONFIG_PATH / GENEMARK_PATH 等。
线程优先级：--threads > per_subcommand_threads > default_cpus（经 --cores 透传）。
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
    "run": "braker.pl：RNA-seq ± 同源蛋白证据的基因预测（BRAKER2）",
    "run_rnaseq": "braker.pl：仅 RNA-seq 证据（BRAKER1 模式）",
    "gtf2gff3": "gtf2gff3.pl：将 braker.gtf 转为 GFF3（stdout）",
}

# 子命令 -> 二进制（惰性解析）
BINARIES = {
    "run": "braker.pl",
    "run_rnaseq": "braker.pl",
    "gtf2gff3": "gtf2gff3.pl",
}

STDOUT_SUBCOMMANDS = {"gtf2gff3"}


class BrakerSkill(base.SkillBase):
    software = "braker"
    binary = "braker.pl"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析所需二进制（braker.pl / gtf2gff3.pl）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def _build_braker(self, subcommand: str, **kw) -> list[str]:
        binary = self._resolve_binary("braker.pl")
        genome = kw.get("genome") or kw.get("input")
        if not genome:
            raise ValueError(f"{subcommand} 缺少必填参数 genome")
        bam = kw.get("bam")
        if subcommand == "run_rnaseq" and not bam:
            raise ValueError("run_rnaseq 缺少必填参数 bam")

        cmd: list[str] = [binary]
        if kw.get("species"):
            cmd.append(f"--species={kw['species']}")
        cmd.append(f"--genome={genome}")
        if bam:
            cmd.append(f"--bam={bam}")
        # run 的 ET 模式可带同源蛋白；run_rnaseq 强制仅 RNA-seq
        if subcommand == "run" and kw.get("prot_seq"):
            cmd.append(f"--prot_seq={kw['prot_seq']}")
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["--cores", str(threads)]
        if subcommand == "run" and kw.get("etpmode"):
            cmd.append("--etpmode")
        if kw.get("softmasking"):
            cmd.append("--softmasking")
        if kw.get("workingdir"):
            cmd.append(f"--workingdir={kw['workingdir']}")
        return cmd

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 BRAKER / gtf2gff3 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        if subcommand in ("run", "run_rnaseq"):
            cmd = self._build_braker(subcommand, **kw)
        else:  # gtf2gff3
            binary = self._resolve_binary("gtf2gff3.pl")
            gtf = kw.get("gtf") or kw.get("input")
            if not gtf:
                raise ValueError("gtf2gff3 缺少必填参数 gtf（输入 GTF）")
            cmd = [binary, str(gtf)]

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
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（经 --cores 透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--extra-args", help="透传给底层程序的额外参数")


def _add_braker_opts(p: argparse.ArgumentParser, *, need_bam: bool = False) -> None:
    p.add_argument("--genome", required=True, help="基因组 FASTA（建议软屏蔽）")
    p.add_argument("--bam", required=need_bam, help="RNA-seq 比对 BAM")
    p.add_argument("--species", help="物种名（AUGUSTUS training 名称）")
    p.add_argument("--workingdir", help="输出目录（默认当前目录）")
    p.add_argument("--softmasking", action="store_true", help="输入基因组已软屏蔽")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="braker-skill",
        description="braker native 技能驱动（braker.pl / gtf2gff3.pl，BRAKER2）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run（BRAKER2：RNA-seq ± 同源蛋白）
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    _add_braker_opts(pr)
    pr.add_argument("--prot_seq", help="同源蛋白序列（ET 模式使用）")
    pr.add_argument("--etpmode", action="store_true", help="ET 模式（结合同源蛋白证据）")
    _add_runtime_opts(pr)

    # run_rnaseq（BRAKER1：仅 RNA-seq）
    p1 = sub.add_parser("run_rnaseq", help=SUBCOMMANDS["run_rnaseq"])
    _add_braker_opts(p1, need_bam=True)
    _add_runtime_opts(p1)

    # gtf2gff3
    pg = sub.add_parser("gtf2gff3", help=SUBCOMMANDS["gtf2gff3"])
    pg.add_argument("gtf", help="输入 GTF（braker.gtf）")
    pg.add_argument("-o", "--output", help="输出 GFF3 路径（stdout 重定向）")
    _add_runtime_opts(pg)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:11s} {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(BrakerSkill().schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BrakerSkill()
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

    # gtf2gff3 的 stdout 落到 --output 文件
    if ns.subcommand in STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
