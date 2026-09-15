#!/usr/bin/env python3
"""trinity native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py denovo --left A1.fq,A2.fq --right A1.fq,A2.fq --seqtype fq --output trinity_denovo --threads 8
   python main.py genome_guided merged.sort.bam --genome-guided-max-intron 4000 --output trinity_genomeGuided --threads 8
   python main.py stats trinity_denovo/Trinity.fasta -o Trinity.fasta.stats
   python main.py abundance_matrix --est_method RSEM --out_prefix genes *.genes.results
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  denovo          Trinity --seqType fq --max_memory <mem> --left ... --right ... --CPU N --output ...
  genome_guided   Trinity --max_memory <mem> --CPU N --genome_guided_bam <bam> --genome_guided_max_intron <n> --output ...
  stats           util/TrinityStats.pl <Trinity.fasta>
  longest_isoforms util/extract_longest_isoforms_from_TrinityFasta.pl <Trinity.fasta>
  align_estimate  util/align_and_estimate_abundance.pl --transcripts ... --est_method RSEM --aln_method bowtie2 --threads N
  abundance_matrix util/abundance_estimates_to_matrix.pl --est_method RSEM --out_prefix genes *.results
所有子命令自动注入线程（--CPU / --threads）与临时目录优化。
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
    "denovo": "Trinity de novo 转录组组装（Inchworm→Chrysalis→Butterfly）",
    "genome_guided": "Trinity 有参（genome-guided）转录组组装",
    "stats": "util/TrinityStats.pl 统计组装结果（contig 数 / N50）",
    "longest_isoforms": "util/extract_longest_isoforms_from_TrinityFasta.pl 提取每基因最长 isoform",
    "align_estimate": "util/align_and_estimate_abundance.pl 比对并估计表达量（RSEM/eXpress）",
    "abundance_matrix": "util/abundance_estimates_to_matrix.pl 合并多样本定量结果为表达矩阵",
}

# 需要主程序 Trinity 二进制的子命令（其余走 install 目录内的 util 脚本）
NEEDS_TRINITY = {"denovo", "genome_guided"}

# util 脚本名映射
UTIL_SCRIPTS = {
    "stats": "TrinityStats.pl",
    "longest_isoforms": "extract_longest_isoforms_from_TrinityFasta.pl",
    "align_estimate": "align_and_estimate_abundance.pl",
    "abundance_matrix": "abundance_estimates_to_matrix.pl",
}

# 子命令把结果写到 stdout、由 main() 重定向到 -o 文件
STDOUT_TO_FILE = {"stats", "longest_isoforms"}


class TrinitySkill(base.SkillBase):
    software = "trinity"
    binary = "Trinity"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_util(self, script_name: str) -> str:
        """解析 Trinity 安装目录内的 util 脚本（先查 PATH，再依 Trinity 二进制定位同级 util/）。"""
        found = base.which(script_name)
        if found:
            return found
        trinity = self._resolve_binary()
        candidate = Path(trinity).resolve().parent / "util" / script_name
        if candidate.exists():
            return str(candidate)
        raise RuntimeError(
            f"未找到 Trinity util 脚本 '{script_name}'（可执行文件 {trinity} 同级 util/ 下未找到）"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 Trinity 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "denovo":
            binary = self._resolve_binary()
            left = kw.get("left")
            if not left:
                raise ValueError("denovo 缺少必填参数 --left（左端 fastq，逗号分隔）")
            cmd: list[str] = [
                binary,
                "--seqType", str(kw.get("seqtype") or "fq"),
                "--max_memory", str(kw.get("max_memory") or "2G"),
                "--left", str(left),
            ]
            if kw.get("right"):
                cmd += ["--right", str(kw["right"])]
            cmd += ["--CPU", str(threads)]
            if kw.get("jaccard_clip"):
                cmd.append("--jaccard_clip")
            if kw.get("normalize_reads"):
                cmd.append("--normalize_reads")
            if kw.get("bfly_calculate_cpu", True):
                cmd.append("--bflyCalculateCPU")
            if kw.get("ss_lib_type"):
                cmd += ["--SS_lib_type", str(kw["ss_lib_type"])]
            if kw.get("output"):
                cmd += ["--output", str(kw["output"])]

        elif subcommand == "genome_guided":
            binary = self._resolve_binary()
            bam = kw.get("genome_guided_bam") or kw.get("bam") or kw.get("input")
            if not bam:
                raise ValueError("genome_guided 缺少必填参数 bam（已排序的基因组比对 BAM）")
            cmd = [
                binary,
                "--max_memory", str(kw.get("max_memory") or "2G"),
                "--CPU", str(threads),
                "--genome_guided_bam", str(bam),
                "--genome_guided_max_intron", str(kw.get("genome_guided_max_intron") or 10000),
            ]
            if kw.get("jaccard_clip"):
                cmd.append("--jaccard_clip")
            if kw.get("normalize_reads"):
                cmd.append("--normalize_reads")
            if kw.get("bfly_calculate_cpu", True):
                cmd.append("--bflyCalculateCPU")
            if kw.get("output"):
                cmd += ["--output", str(kw["output"])]

        elif subcommand in ("stats", "longest_isoforms"):
            script = self._resolve_util(UTIL_SCRIPTS[subcommand])
            fasta = kw.get("fasta") or kw.get("input")
            if not fasta:
                raise ValueError(f"{subcommand} 缺少必填参数 fasta（Trinity.fasta）")
            cmd = [script, str(fasta)]

        elif subcommand == "align_estimate":
            script = self._resolve_util(UTIL_SCRIPTS["align_estimate"])
            transcripts = kw.get("transcripts")
            if not transcripts:
                raise ValueError("align_estimate 缺少必填参数 --transcripts（Trinity.fasta）")
            cmd = [
                script,
                "--transcripts", str(transcripts),
                "--seqType", str(kw.get("seqtype") or "fq"),
            ]
            if kw.get("left"):
                cmd += ["--left", str(kw["left"])]
            if kw.get("right"):
                cmd += ["--right", str(kw["right"])]
            cmd += [
                "--est_method", str(kw.get("est_method") or "RSEM"),
                "--aln_method", str(kw.get("aln_method") or "bowtie2"),
                "--threads", str(threads),
            ]
            if kw.get("ss_lib_type"):
                cmd += ["--SS_lib_type", str(kw["ss_lib_type"])]
            if kw.get("output_dir"):
                cmd += ["--output_dir", str(kw["output_dir"])]

        else:  # abundance_matrix
            script = self._resolve_util(UTIL_SCRIPTS["abundance_matrix"])
            results = kw.get("results") or []
            if not results:
                raise ValueError("abundance_matrix 缺少必填参数 results（各样本 *.results 列表）")
            cmd = [
                script,
                "--est_method", str(kw.get("est_method") or "RSEM"),
                "--out_prefix", str(kw.get("out_prefix") or "genes"),
                "--threads", str(threads),
            ]
            cmd += [str(r) for r in results]

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
        prog="trinity-skill",
        description="trinity native 技能驱动（自动线程/内存/IO 优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # denovo
    pd = sub.add_parser("denovo", help=SUBCOMMANDS["denovo"])
    pd.add_argument("--left", required=True, help="左端 fastq（多样本逗号分隔）")
    pd.add_argument("--right", help="右端 fastq（多样本逗号分隔）")
    pd.add_argument("--seqtype", default="fq", choices=["fq", "fa"], help="序列类型（默认 fq）")
    pd.add_argument("--max-memory", default="2G", help="最大内存（如 2G/20G，默认 2G）")
    pd.add_argument("--jaccard-clip", action="store_true", help="开启 --jaccard_clip（基因密集物种）")
    pd.add_argument("--normalize-reads", action="store_true", help="开启 --normalize_reads")
    pd.add_argument("--ss-lib-type", help="链特异性类型（如 RF/FR）")
    pd.add_argument("--no-bfly-calculate-cpu", dest="bfly_calculate_cpu", action="store_false",
                    help="关闭 --bflyCalculateCPU")
    pd.add_argument("-o", "--output", help="输出目录（默认 trinity_out_dir）")
    pd.add_argument("--extra-args", help="透传给 Trinity 的额外参数")
    _add_runtime_opts(pd)

    # genome_guided
    pg = sub.add_parser("genome_guided", help=SUBCOMMANDS["genome_guided"])
    pg.add_argument("bam", nargs="?", help="已排序基因组比对 BAM（别名 --genome-guided-bam）")
    pg.add_argument("--genome-guided-bam", help="已排序基因组比对 BAM 的别名")
    pg.add_argument("--genome-guided-max-intron", type=int, default=10000, help="最大内含子长度（默认 10000）")
    pg.add_argument("--max-memory", default="2G", help="最大内存（默认 2G）")
    pg.add_argument("--jaccard-clip", action="store_true", help="开启 --jaccard_clip")
    pg.add_argument("--normalize-reads", action="store_true", help="开启 --normalize_reads")
    pg.add_argument("--no-bfly-calculate-cpu", dest="bfly_calculate_cpu", action="store_false",
                    help="关闭 --bflyCalculateCPU")
    pg.add_argument("-o", "--output", help="输出目录")
    pg.add_argument("--extra-args", help="透传给 Trinity 的额外参数")
    _add_runtime_opts(pg)

    # stats / longest_isoforms
    ps = sub.add_parser("stats", help=SUBCOMMANDS["stats"])
    ps.add_argument("fasta", help="Trinity.fasta / Trinity-GG.fasta")
    ps.add_argument("-o", "--output", help="统计结果输出文件（默认 stdout）")
    _add_runtime_opts(ps)

    pl = sub.add_parser("longest_isoforms", help=SUBCOMMANDS["longest_isoforms"])
    pl.add_argument("fasta", help="Trinity.fasta")
    pl.add_argument("-o", "--output", help="最长 isoform FASTA 输出文件（默认 stdout）")
    _add_runtime_opts(pl)

    # align_estimate
    pa = sub.add_parser("align_estimate", help=SUBCOMMANDS["align_estimate"])
    pa.add_argument("--transcripts", required=True, help="Trinity.fasta")
    pa.add_argument("--seqtype", default="fq", choices=["fq", "fa"], help="序列类型（默认 fq）")
    pa.add_argument("--left", help="左端 fastq")
    pa.add_argument("--right", help="右端 fastq")
    pa.add_argument("--est-method", default="RSEM", choices=["RSEM", "eXpress"], help="表达量估计方法")
    pa.add_argument("--aln-method", default="bowtie2", choices=["bowtie", "bowtie2"], help="比对方法")
    pa.add_argument("--ss-lib-type", help="链特异性类型")
    pa.add_argument("--output-dir", help="输出目录")
    pa.add_argument("--extra-args", help="透传给 align_and_estimate_abundance.pl 的额外参数")
    _add_runtime_opts(pa)

    # abundance_matrix
    pm = sub.add_parser("abundance_matrix", help=SUBCOMMANDS["abundance_matrix"])
    pm.add_argument("results", nargs="+", help="各样本定量结果（*.genes.results / *.isoforms.results）")
    pm.add_argument("--est-method", default="RSEM", choices=["RSEM", "kallisto", "salmon", "eXpress"],
                    help="定量结果来源方法")
    pm.add_argument("--out-prefix", default="genes", help="输出前缀（默认 genes）")
    pm.add_argument("--extra-args", help="透传给 abundance_estimates_to_matrix.pl 的额外参数")
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
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = TrinitySkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TrinitySkill()
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

    # stats / longest_isoforms 的 stdout 落到 -o 文件（util 脚本写 stdout）
    if ns.subcommand in STDOUT_TO_FILE and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
