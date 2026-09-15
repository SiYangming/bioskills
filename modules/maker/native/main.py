#!/usr/bin/env python3
"""maker native 标准入口驱动。

MAKER 综合基因注释流水线的自包含驱动，覆盖 4 个子命令：
  ctl           maker -CTL                                  （生成 maker_opts.ctl 等配置模板）
  run           [mpiexec -n <threads>] maker <genome> ...   （运行注释，可 MPI 并行）
  merge         gff3_merge -d <..._master_datastore_index.log> [-o out]   （汇总 GFF）
  fasta_merge   fasta_merge -d <..._master_datastore_index.log>           （汇总 FASTA）

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py ctl
   python main.py run genome.fasta -est Trinity.fasta -protein homolog.fasta --mpi --threads 8
   python main.py merge genome.maker.output/genome_master_datastore_index.log -o genome.all.gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

依赖：AUGUSTUS / SNAP / GeneMark-ES/ET / RepeatMasker / RepeatModeler / tRNAscan-SE / exonerate / MPI。
线程优先级：--threads > per_subcommand_threads > default_cpus（仅 mpi 模式经 mpiexec -n 透传）。
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
    "ctl": "maker -CTL：生成 maker_opts.ctl / maker_exe.ctl / maker_bopts.ctl 配置模板",
    "run": "maker：运行 MAKER 注释（可 mpiexec 并行）",
    "merge": "gff3_merge -d：汇总各分区结果为一个 GFF",
    "fasta_merge": "fasta_merge -d：汇总各分区结果为 transcript/cds/protein FASTA",
}

# 子命令 -> 二进制（惰性解析）
BINARIES = {
    "ctl": "maker",
    "run": "maker",
    "merge": "gff3_merge",
    "fasta_merge": "fasta_merge",
}


class MakerSkill(base.SkillBase):
    software = "maker"
    binary = "maker"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析所需二进制（maker/gff3_merge/fasta_merge/mpiexec）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 MAKER 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = []

        if subcommand == "ctl":
            cmd = [self._resolve_binary("maker"), "-CTL"]

        elif subcommand == "run":
            maker = self._resolve_binary("maker")
            if kw.get("mpi"):
                threads = self._effective_threads(subcommand, kw.get("threads"))
                cmd = [self._resolve_binary("mpiexec"), "-n", str(threads), maker]
            else:
                cmd = [maker]
            if kw.get("base"):
                cmd += ["-base", str(kw["base"])]
            if kw.get("fix_nucleotides"):
                cmd.append("-fix_nucleotides")
            genome = kw.get("genome") or kw.get("input")
            if genome:
                cmd.append(str(genome))
            for flag, key in (("-est", "est"), ("-protein", "protein"),
                              ("-model_org", "model_org"), ("-rmlib", "rmlib"),
                              ("-augustus_species", "augustus_species"),
                              ("-snaphmm", "snaphmm"), ("-gmhmm", "gmhmm")):
                if kw.get(key):
                    cmd += [flag, str(kw[key])]
            for flag in ("-est2genome", "-protein2genome", "-trna"):
                if kw.get(flag.lstrip("-")):
                    cmd.append(flag)

        else:  # merge / fasta_merge
            binary = self._resolve_binary(BINARIES[subcommand])
            log = kw.get("datastore_index_log") or kw.get("input")
            if not log:
                raise ValueError(f"{subcommand} 缺少必填参数 datastore_index_log（-d）")
            cmd = [binary, "-d", str(log)]
            if subcommand == "merge" and kw.get("output"):
                cmd += ["-o", str(kw["output"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅 run --mpi 经 mpiexec -n 透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--extra-args", help="透传给底层程序的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="maker-skill",
        description="maker native 技能驱动（ctl/run/merge/fasta_merge）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # ctl
    pc = sub.add_parser("ctl", help=SUBCOMMANDS["ctl"])
    _add_runtime_opts(pc)

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("genome", nargs="?", help="基因组 FASTA（不提供则读取 maker_opts.ctl）")
    pr.add_argument("-est", help="EST / 转录本序列")
    pr.add_argument("-protein", help="同源蛋白序列")
    pr.add_argument("-model_org", help="重复序列模型物种（如 fungi）")
    pr.add_argument("-rmlib", help="RepeatModeler 自定义重复库")
    pr.add_argument("-augustus_species", help="AUGUSTUS 物种参数名")
    pr.add_argument("-snaphmm", help="SNAP HMM 模型文件")
    pr.add_argument("-gmhmm", help="GeneMark HMM 模型文件（.mod）")
    pr.add_argument("-est2genome", action="store_true", help="直接用 EST 证据预测")
    pr.add_argument("-protein2genome", action="store_true", help="直接用蛋白证据预测")
    pr.add_argument("-trna", action="store_true", help="预测 tRNA")
    pr.add_argument("-fix_nucleotides", dest="fix_nucleotides", action="store_true", help="修正非 ACGT 字符")
    pr.add_argument("-base", dest="base", help="输出前缀")
    pr.add_argument("--mpi", action="store_true", help="以 mpiexec -n <threads> 并行执行")
    _add_runtime_opts(pr)

    # merge
    pm = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pm.add_argument("datastore_index_log", help="<genome>_master_datastore_index.log")
    pm.add_argument("-o", "--output", help="输出 GFF 文件名（默认 genome.all.gff）")
    _add_runtime_opts(pm)

    # fasta_merge
    pf = sub.add_parser("fasta_merge", help=SUBCOMMANDS["fasta_merge"])
    pf.add_argument("datastore_index_log", help="<genome>_master_datastore_index.log")
    _add_runtime_opts(pf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(MakerSkill().schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MakerSkill()
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
