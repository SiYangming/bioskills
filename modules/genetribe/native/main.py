#!/usr/bin/env python3
"""genetribe native 标准入口驱动（继承 base.SkillBase）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py core -l aet -f rice --threads 8 --tmpdir /tmp
   python main.py sameassembly -l IWGSCv1p1 -f IWGSCv1
   python main.py RBH -a A_vs_B.score -b B_vs_A.score
   python main.py CBS -i aet.rice.lifted.anchors -a aet.bed -b rice.bed -o aet_rice
   python main.py longestcds -i A.pep.all.fa -s .
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py <sub> ... --dry-run   # 只打印构建出的命令，不执行

子命令与参数对齐上游 `genetribe` 入口脚本（chenym1/genetribe v1.2.1，2026-09-07 官方
src/*.sh|*.py 与 chenym1.github.io/genetribe/tutorial 核实；主程序调用形态：
`genetribe <command> [options]`，pipeline 类运行于当前目录、要求前缀文件就地就位）：
  core           genetribe core -l <A> -f <B> [-d blastdir] [-r] [-c] [-s sep] [-e E] [-n th] [-b BSR] [-m]
  corenog        genetribe corenog -l <A> -f <B> [-d blastdir] [-c] [-s sep] [-e E] [-n th] [-b BSR]
  sameassembly   genetribe sameassembly -l <A> -f <B>     （需 <A>.bed/.genelength 等）
  RBH            genetribe RBH -a <blast1> -b <blast2>    （三列 tab：q s score；结果打 stdout）
  CBS            genetribe CBS -i <anchors> -a <bed1> -b <bed2> -o <out>（产出 <out>.collinearity_info）
  longestcds     genetribe longestcds -i <pep.fa> [-s sep]（结果打 stdout）
说明：上游 -n 为 blastp 线程、默认 36（core.sh/corenog.sh getopts 核实）；本驱动仅在用户显式给出
--threads 时注入 -n，缺省不传（沿用上游默认 36）。sameassembly/RBH/CBS/longestcds 上游无 -n，
--threads 在它们上不注入（仅占位接受，供调度器统一读取）。
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

# 子命令语义清单（用于 --list-commands 与 Schema description；与上游 `genetribe -h` 输出一致）
SUBCOMMANDS = {
    "core": "GeneTribe 主流程（跨物种，按染色体组计分；输入 <A>/<B>.bed/.fa/.chrlist 等）",
    "corenog": "不分染色体组的工作流（core 的简化变体）",
    "sameassembly": "同一组装内的同源推断（输入 <A>/<B>.bed + .genelength）",
    "RBH": "计算双向最佳命中（输入两份 q\\ts\\tscore 表，结果打 stdout）",
    "CBS": "计算共线性块得分（输入 anchors + 两个 bed）",
    "longestcds": "从蛋白 FASTA 提取每基因最长转录本（结果打 stdout）",
}

# 主流程子命令（带 -l/-f 前缀参数且可注入 -n 的 pipeline）
_PIPELINE_CMDS = ("core", "corenog", "sameassembly")
# 接受 -n（blastp 线程）的子命令
_NTHREAD_CMDS = ("core", "corenog")


def _add_optional(cmd: list[str], flag: str, val: object) -> None:
    """仅当 val 非空时追加 '-<flag> <val>'。"""
    if val is not None and str(val) != "":
        cmd += [flag, str(val)]


class GeneTribeSkill(base.SkillBase):
    software = "genetribe"
    binary = "genetribe"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 genetribe 命令行（代理上游入口脚本）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary, subcommand]
        threads = kw.get("threads")

        if subcommand in ("core", "corenog"):
            first = kw.get("first_prefix") or kw.get("l")
            second = kw.get("second_prefix") or kw.get("f")
            if not first or not second:
                raise ValueError(f"{subcommand} 需要 -l <前缀1> 与 -f <前缀2>（两物种文件前缀）")
            cmd += ["-l", str(first), "-f", str(second)]
            _add_optional(cmd, "-d", kw.get("blast_dir"))
            if subcommand == "core" and kw.get("no_chr_group"):
                cmd.append("-r")  # 上游 -r：不算染色体组得分（默认计分）
            if kw.get("confidence"):
                cmd.append("-c")  # 计算置信度分（需 <prefix>.confidence）
            _add_optional(cmd, "-s", kw.get("split_sep") or kw.get("s"))
            _add_optional(cmd, "-e", kw.get("evalue"))
            if threads is not None:  # 显式 --threads 才注入 -n（缺省沿用上游默认 36）
                cmd += ["-n", str(threads)]
            _add_optional(cmd, "-b", kw.get("bsr_threshold"))
            if subcommand == "core" and kw.get("no_collinearity"):
                cmd.append("-m")  # 上游 -m：不使用共线性加权（默认加权）
        elif subcommand == "sameassembly":
            first = kw.get("first_prefix") or kw.get("l")
            second = kw.get("second_prefix") or kw.get("f")
            if not first or not second:
                raise ValueError("sameassembly 需要 -l <前缀1> 与 -f <前缀2>")
            cmd += ["-l", str(first), "-f", str(second)]
        elif subcommand == "RBH":
            a = kw.get("blast1")
            b = kw.get("blast2")
            if not a or not b:
                raise ValueError("RBH 需要 -a <blast1> 与 -b <blast2>（q\\ts\\tscore 表）")
            cmd += ["-a", str(a), "-b", str(b)]
        elif subcommand == "CBS":
            anchors = kw.get("anchors")
            bed_a = kw.get("bed1")
            bed_b = kw.get("bed2")
            out = kw.get("cbs_out")
            if not anchors or not bed_a or not bed_b or not out:
                raise ValueError("CBS 需要 -i <anchors> -a <bed1> -b <bed2> -o <输出前缀>")
            cmd += ["-i", str(anchors), "-a", str(bed_a), "-b", str(bed_b), "-o", str(out)]
        elif subcommand == "longestcds":
            pep = kw.get("pep")
            if not pep:
                raise ValueError("longestcds 需要 -i <pep.fa>（蛋白 FASTA）")
            cmd += ["-i", str(pep)]
            _add_optional(cmd, "-s", kw.get("split_sep") or kw.get("s"))

        # 高级透传（慎用；追加到子命令参数尾部，可覆盖同名字段）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genetribe-skill",
        description="genetribe native 技能驱动（core / corenog / sameassembly / RBH / CBS / longestcds）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # core / corenog（主流程，跨物种）
    for name in ("core", "corenog"):
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("-l", "--first-prefix", dest="first_prefix",
                        help=f"{name} 第一个物种文件前缀（需 <前缀>.bed/.fa/.chrlist 等在运行目录）")
        ps.add_argument("-f", "--second-prefix", dest="second_prefix", help="第二个物种文件前缀")
        ps.add_argument("-d", "--blast-dir", dest="blast_dir", default=None,
                        help="预计算 BLAST 结果目录（默认 ./；缺省则由流程自行 makeblastdb + blastp）")
        ps.add_argument("-e", "--evalue", default=None, help="blastp E-value（上游默认 1e-5）")
        ps.add_argument("-s", "--split-sep", dest="split_sep", default=None,
                        help="从 transcript ID 切 gene ID 的分隔符（上游默认 .）")
        ps.add_argument("-b", "--bsr-threshold", dest="bsr_threshold", type=float, default=None,
                        help="BSR 同源匹配分过滤阈值 0-100（上游默认 75）")
        ps.add_argument("-c", "--confidence", action="store_true",
                        help="计算置信度分（需要 <前缀>.confidence 文件）")
        if name == "core":
            ps.add_argument("-r", "--no-chr-group", action="store_true",
                            help="不算染色体组得分（上游默认计分，加 -r 关闭）")
            ps.add_argument("-m", "--no-collinearity", action="store_true",
                            help="不使用共线性权重（上游默认加权，加 -m 关闭）")
        ps.add_argument("--extra-args", help="透传给 genetribe 的额外参数")
        _add_runtime_opts(ps)

    # sameassembly
    psa = sub.add_parser("sameassembly", help=SUBCOMMANDS["sameassembly"])
    psa.add_argument("-l", "--first-prefix", dest="first_prefix", help="第一个组装文件前缀")
    psa.add_argument("-f", "--second-prefix", dest="second_prefix", help="第二个组装文件前缀")
    psa.add_argument("--extra-args", help="透传给 genetribe 的额外参数")
    _add_runtime_opts(psa)

    # RBH
    prb = sub.add_parser("RBH", help=SUBCOMMANDS["RBH"])
    prb.add_argument("-a", "--blast1", dest="blast1", help="方向 1 的 BLAST/score 表（q\\ts\\tscore）")
    prb.add_argument("-b", "--blast2", dest="blast2", help="方向 2 的 BLAST/score 表（q\\ts\\tscore）")
    _add_runtime_opts(prb)

    # CBS
    pcbs = sub.add_parser("CBS", help=SUBCOMMANDS["CBS"])
    pcbs.add_argument("-i", "--anchors", dest="anchors", help="输入 anchors 文件（MCScan lifted anchors）")
    pcbs.add_argument("-a", "--bed1", dest="bed1", help="物种 1 六列 bed")
    pcbs.add_argument("-b", "--bed2", dest="bed2", help="物种 2 六列 bed")
    pcbs.add_argument("-o", "--cbs-out", dest="cbs_out", help="输出前缀（<out>.collinearity_info 等）")
    _add_runtime_opts(pcbs)

    # longestcds
    plc = sub.add_parser("longestcds", help=SUBCOMMANDS["longestcds"])
    plc.add_argument("-i", "--pep", dest="pep", help="输入蛋白 FASTA（转录本级）")
    plc.add_argument("-s", "--split-sep", dest="split_sep", default=None,
                     help="从 transcript ID 切 gene ID 的分隔符（上游默认 .）")
    _add_runtime_opts(plc)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖 blastp 线程数（core/corenog 经上游 -n 注入；缺省沿用上游默认 36）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GeneTribeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GeneTribeSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
        return 0

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
