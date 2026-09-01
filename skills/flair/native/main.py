#!/usr/bin/env python3
"""flair native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py bam2bed12 -i sample.sorted.bam -o sample.bed12 --threads 4
   python main.py annotate sample.bed12 gencode.v49.annotation.gtf sample.annotated.bed
   python main.py collapse -q sample.annotated.bed -g hg38.fa -r sample.fastq.gz \
       -o out/sample -f gencode.v49.annotation.gtf -s 3 -w 100 --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh：
  Step1  bam2Bed12 -i <bam> > <bed12>
  Step2  identify_gene_isoform <bed12> <gtf> <annotated_bed>
  Step3  flair collapse -q <annotated_bed> -g <genome> -r <reads> -o <prefix> -t N
         -f <gtf> -s <min_support> -w <end_window> --trust_ends --remove_internal_priming
         --intprimingthreshold N --stringent --check_splice --mm2_args=... --quiet
所有子命令自动注入线程（-t）与临时目录优化。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 skills/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令 -> 实际可执行文件（flair conda 包内三个可执行）
SUBCOMMAND_BIN = {
    "bam2bed12": "bam2Bed12",
    "annotate": "identify_gene_isoform",
    "collapse": "flair",
}

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "bam2bed12": "BAM -> BED12（bam2Bed12，isoform 剪接结构转换）",
    "annotate": "BED12 + GTF -> 带基因注释 BED（identify_gene_isoform）",
    "collapse": "带注释 BED + genome + reads -> 一致性转录本 FASTA（flair collapse）",
}


class FlairSkill(base.SkillBase):
    software = "flair"
    binary = "flair"  # collapse 主命令；bam2bed12/annotate 子命令各自解析其它二进制

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_subcommand_bin(self, subcommand: str) -> str:
        bin_name = SUBCOMMAND_BIN.get(subcommand, self.binary)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'（子命令 {subcommand}），请先通过 Conda/Docker/Apptainer 安装 flair。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 flair 命令行。"""
        if subcommand not in SUBCOMMAND_BIN:
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_subcommand_bin(subcommand)
        cmd: list[str] = [binary]

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "bam2bed12":
            # bam2Bed12 -i <bam> > <bed12>
            bam = kw.get("input") or kw.get("bam")
            if not bam:
                raise ValueError("bam2bed12 缺少必填参数 input（sorted BAM）")
            cmd += ["-i", str(bam)]
            # 输出：bam2Bed12 写 stdout，由 main() 捕获后写入 output 文件

        elif subcommand == "annotate":
            # identify_gene_isoform <bed12> <gtf> <annotated_bed>
            bed12 = kw.get("input") or kw.get("bed12")
            gtf = kw.get("gtf")
            out = kw.get("output") or kw.get("annotated_bed")
            if not bed12 or not gtf:
                raise ValueError("annotate 缺少必填参数 input(bed12) 与 gtf")
            cmd += [str(bed12), str(gtf)]
            if out:
                cmd.append(str(out))

        elif subcommand == "collapse":
            # flair collapse -q <annotated_bed> -g <genome> -r <reads> -o <prefix> -t N
            #   -f <gtf> -s <min_support> -w <end_window> --trust_ends
            #   --remove_internal_priming --intprimingthreshold N --stringent
            #   --check_splice --mm2_args=... --quiet
            annotated_bed = kw.get("annotated_bed") or kw.get("input") or kw.get("q")
            genome = kw.get("genome") or kw.get("g")
            reads = kw.get("reads") or kw.get("r")
            if not annotated_bed or not genome or not reads:
                raise ValueError("collapse 缺少必填参数 annotated_bed / genome / reads")
            prefix = kw.get("prefix") or kw.get("output")
            if not prefix:
                sample = Path(reads).stem.replace(".fastq", "").replace(".gz", "")
                prefix = f"{sample}.collapse"
            cmd += ["collapse"]
            cmd += ["-q", str(annotated_bed)]
            cmd += ["-g", str(genome)]
            cmd += ["-r", str(reads)]
            cmd += ["-o", str(prefix)]
            cmd += ["-t", str(threads)]
            gtf = kw.get("gtf")
            if gtf:
                cmd += ["-f", str(gtf)]
            if kw.get("min_support") is not None:
                cmd += ["-s", str(kw["min_support"])]
            if kw.get("end_window") is not None:
                cmd += ["-w", str(kw["end_window"])]
            if kw.get("intpriming_threshold") is not None:
                cmd += ["--intprimingthreshold", str(kw["intpriming_threshold"])]
            # 布尔开关：默认开启（与 nanoseq 脚本一致）
            if kw.get("trust_ends", True):
                cmd.append("--trust_ends")
            if kw.get("remove_internal_priming", True):
                cmd.append("--remove_internal_priming")
            if kw.get("stringent", True):
                cmd.append("--stringent")
            if kw.get("check_splice", True):
                cmd.append("--check_splice")
            if kw.get("quiet", True):
                cmd.append("--quiet")
            mm2 = kw.get("mm2_args")
            if mm2:
                cmd += ["--mm2_args", str(mm2)]

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
        prog="flair-skill",
        description="flair native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # bam2bed12
    pb = sub.add_parser("bam2bed12", help=SUBCOMMANDS["bam2bed12"])
    pb.add_argument("-i", "--input", help="输入 sorted BAM")
    pb.add_argument("-o", "--output", help="输出 BED12 文件（bam2Bed12 写 stdout，由驱动重定向）")
    _add_runtime_opts(pb)

    # annotate
    pa = sub.add_parser("annotate", help=SUBCOMMANDS["annotate"])
    pa.add_argument("input", nargs="?", help="输入 BED12 文件")
    pa.add_argument("--bed12", help="输入 BED12 文件的别名")
    pa.add_argument("-f", "--gtf", help="参考注释 GTF")
    pa.add_argument("-o", "--output", help="输出带注释 BED 文件")
    pa.add_argument("--annotated-bed", help="输出带注释 BED 的别名")
    _add_runtime_opts(pa)

    # collapse
    pc = sub.add_parser("collapse", help=SUBCOMMANDS["collapse"])
    pc.add_argument("-q", "--annotated-bed", help="带基因注释 BED（annotate 输出）")
    pc.add_argument("-g", "--genome", help="参考基因组 FASTA")
    pc.add_argument("-r", "--reads", help="原始 reads（FASTQ/FASTA，支持 .gz）")
    pc.add_argument("-o", "--output", help="输出前缀（默认 <sample>.collapse）")
    pc.add_argument("-f", "--gtf", help="参考注释 GTF")
    pc.add_argument("-s", "--min-support", type=int, help="最小 read 支持数（默认 3）")
    pc.add_argument("-w", "--end-window", type=int, help="3'/5' 端窗口（默认 100）")
    pc.add_argument("--intpriming-threshold", type=int, help="内部加尾修剪阈值（默认 30）")
    pc.add_argument("--no-trust-ends", dest="trust_ends", action="store_false", help="关闭 --trust_ends")
    pc.add_argument("--no-remove-internal-priming", dest="remove_internal_priming", action="store_false", help="关闭 --remove_internal_priming")
    pc.add_argument("--no-stringent", dest="stringent", action="store_false", help="关闭 --stringent")
    pc.add_argument("--no-check-splice", dest="check_splice", action="store_false", help="关闭 --check_splice")
    pc.add_argument("--no-quiet", dest="quiet", action="store_false", help="关闭 --quiet")
    pc.add_argument("--mm2-args", help="minimap2 参数（逗号分隔，默认 -I8g,--MD）")
    pc.add_argument("--extra-args", help="透传给 flair 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pc)

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
        skill = FlairSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FlairSkill()
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

    # bam2bed12 的 stdout 落到 output 文件（bam2Bed12 写 stdout）
    if ns.subcommand == "bam2bed12" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
