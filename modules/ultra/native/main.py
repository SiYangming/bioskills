#!/usr/bin/env python3
"""ultra native 标准入口驱动。

命令逻辑：
  - ULTRA_align.py（subcmd_gunzip / subcmd_index / subcmd_align / subcmd_sort，历史实现）
  - modules/ultra/snakemake/（ultra_sort_gtf / ultra_index / ultra_align 单规则 .smk，td2 式）

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py gunzip reads.fa.gz -o reads.fa
   python main.py index genome.fa genes.sorted.gtf idx_dir --args "--disable_infer"
   python main.py align genome.fa reads.fa aln_dir --index idx_dir --prefix sample --threads 8
   python main.py sort genes.gtf --outdir . --prefix genes
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

运行前提：PATH 中可解析 uLTRA、samtools、minimap2、namfinder（conda env：
  mamba create -n ultra-native -c conda-forge -c bioconda ultra_bioinformatics minimap2 samtools）。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
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
    "gunzip": "解压 .gz 序列/注释文件（gzip -cd <in.gz> > <out>）",
    "index": "uLTRA index <fasta> <gtf> <outdir> [--disable_infer] 生成 *.pickle 与 *.db",
    "align": "uLTRA align <genome> <reads> <outdir> --t N --prefix <p> --index <dir> | samtools sort -> BAM",
    "sort": "GTF 排序 sort -k1,1 -k4,4n <in.gtf> > <out>.sorted.gtf（index 前置步骤）",
}

GZIP_EXTS = (".fa.gz", ".fasta.gz", ".fastq.gz", ".gtf.gz")


class UltraSkill(base.SkillBase):
    software = "ultra"
    binary = "uLTRA"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    # -- 工具 -------------------------------------------------------------- #
    @staticmethod
    def _q(p: str) -> str:
        return shlex.quote(str(p))

    def _resolve_align_deps(self) -> dict[str, str]:
        """align 前预检 minimap2 / namfinder / samtools，并把其目录并入 PATH。

        与 ULTRA_align.py 行为一致：uLTRA 在预过滤中调用 minimap2、在 NAM 查找中
        调用 namfinder；缺失时给出明确的 conda 安装提示。
        """
        deps: dict[str, str] = {}
        for name in ("minimap2", "namfinder", "samtools"):
            path = shutil.which(name)
            if not path:
                raise RuntimeError(
                    f"未检测到 {name}（uLTRA align 需要）。请安装 ultra_bioinformatics 及其依赖：\n"
                    "  mamba install -c conda-forge -c bioconda ultra_bioinformatics=0.1 minimap2 namfinder samtools"
                )
            deps[name] = path
        extra_dirs = sorted({str(Path(p).parent) for p in deps.values()})
        cur = self.env_vars.get("PATH") or os.environ.get("PATH", "")
        self.env_vars["PATH"] = ":".join(extra_dirs + [cur])
        return deps

    # -- 子命令命令构建 ---------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建命令行（返回 bash 脚本，保留源实现的 shell 语义）。"""
        if subcommand == "gunzip":
            return self._cmd_gunzip(**kw)
        if subcommand == "index":
            return self._cmd_index(**kw)
        if subcommand == "align":
            return self._cmd_align(**kw)
        if subcommand == "sort":
            return self._cmd_sort(**kw)
        raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _cmd_gunzip(self, **kw) -> list[str]:
        # gzip -cd <in.gz> > <out>；out 默认 = 输入去掉 .gz
        archive = kw.get("input")
        if not archive:
            raise RuntimeError("gunzip 需要输入 .gz 文件（input）")
        archive = str(archive)
        if not archive.endswith(".gz"):
            raise RuntimeError("gunzip 子命令要求输入以 .gz 结尾的文件")
        out = kw.get("output") or archive[:-3]
        args = str(kw.get("args") or "").strip()
        script = f"gzip -cd {args} {self._q(archive)} > {self._q(out)}"
        return ["bash", "-o", "pipefail", "-c", script]

    def _cmd_index(self, **kw) -> list[str]:
        # uLTRA index <fasta> <gtf> <outdir> [--disable_infer]
        fasta = kw.get("fasta")
        gtf = kw.get("gtf")
        outdir = kw.get("outdir")
        if not fasta or not gtf or not outdir:
            raise RuntimeError("index 需要 --fasta <fa> --gtf <gtf> --outdir <dir>")
        args = str(kw.get("args") or "--disable_infer").strip()
        ultra = self._resolve_binary()
        outdir_p = Path(outdir)
        outdir_p.mkdir(parents=True, exist_ok=True)

        steps: list[str] = [f"mkdir -p {self._q(str(outdir_p))}"]
        fasta_for_index = str(fasta)
        # 若参考 FASTA 为压缩格式，先解压到 outdir（避免 uLTRA index 读取失败）
        if fasta_for_index.endswith(GZIP_EXTS):
            dec = outdir_p / self._decompressed_name(fasta_for_index)
            steps.append(
                f"gzip -cd {self._q(fasta_for_index)} > {self._q(str(dec))}"
            )
            fasta_for_index = str(dec)
        # 在 outdir 中运行，与 nf-core / isoseq 行为保持一致
        steps.append(
            f"cd {self._q(str(outdir_p))} && {self._q(ultra)} index "
            f"{self._q(fasta_for_index)} {self._q(str(gtf))} ./ {args}"
        )
        return ["bash", "-o", "pipefail", "-c", " && ".join(steps)]

    def _cmd_align(self, **kw) -> list[str]:
        # uLTRA align <genome> <reads> <outdir> --t N --prefix <p> --index <idx> && samtools sort
        reads = kw.get("reads")
        genome = kw.get("genome")
        index_dir = kw.get("index_dir")
        outdir = kw.get("outdir")
        if not reads or not genome or not index_dir or not outdir:
            raise RuntimeError("align 需要 --reads <reads> --genome <fa> --index-dir <idx> --outdir <dir>")
        ultra = self._resolve_binary()
        deps = self._resolve_align_deps()
        threads = self._effective_threads("align", kw.get("threads"))
        prefix = kw.get("prefix") or self._default_prefix(str(reads))
        args = str(kw.get("args") or "").strip()
        args2 = str(kw.get("args2") or "").strip()

        outdir_p = Path(outdir)
        outdir_p.mkdir(parents=True, exist_ok=True)
        idx_p = Path(index_dir)

        steps: list[str] = [f"mkdir -p {self._q(str(outdir_p))}"]
        # 将索引文件复制到 outdir（与 nf-core 模块在工作目录读取索引一致）
        steps.append(
            f"cp {self._q(str(idx_p / '*.pickle'))} {self._q(str(idx_p / '*.db'))} {self._q(str(outdir_p))}"
        )

        genome_for_align = str(genome)
        if genome_for_align.endswith(GZIP_EXTS):
            dec = outdir_p / self._decompressed_name(genome_for_align)
            steps.append(f"gzip -cd {self._q(genome_for_align)} > {self._q(str(dec))}")
            genome_for_align = str(dec)

        reads_for_align = str(reads)
        if reads_for_align.endswith(GZIP_EXTS):
            dec = outdir_p / self._decompressed_name(reads_for_align)
            steps.append(f"gzip -cd {self._q(reads_for_align)} > {self._q(str(dec))}")
            reads_for_align = str(dec)

        # uLTRA align（在 outdir 内执行，--index ./ 指向复制过来的索引）→ samtools sort → BAM
        steps.append(
            f"cd {self._q(str(outdir_p))} && "
            f"{self._q(ultra)} align {self._q(genome_for_align)} {self._q(reads_for_align)} ./ "
            f"--t {threads} --prefix {self._q(prefix)} --index ./ {args} && "
            f"{self._q(deps['samtools'])} sort --threads {threads} -o {self._q(f'{prefix}.bam')} -O BAM "
            f"{args2} {self._q(f'{prefix}.sam')} && "
            f"rm -f {self._q(f'{prefix}.sam')}"
        )
        return ["bash", "-o", "pipefail", "-c", " && ".join(steps)]

    def _cmd_sort(self, **kw) -> list[str]:
        # sort -k1,1 -k4,4n <in.gtf> > <out>.sorted.gtf（index 前置步骤）
        gtf = kw.get("input") or kw.get("gtf")
        if not gtf:
            raise RuntimeError("sort 需要输入 GTF（input / --gtf）")
        gtf = str(gtf)
        outdir = Path(kw.get("outdir") or ".")
        outdir.mkdir(parents=True, exist_ok=True)
        prefix = kw.get("prefix") or self._gtf_stem(gtf)
        output_file = outdir / f"{prefix}.sorted.gtf"
        args = str(kw.get("args") or "").strip()

        if gtf.endswith(".gz"):
            # 使用 bash -o pipefail 确保上游 gzip 失败时整体报错，而不是生成空文件
            script = (
                f"LC_ALL=C gzip -cd {self._q(gtf)} | "
                f"sort {args} -k1,1 -k4,4n > {self._q(str(output_file))}"
            )
            return ["bash", "-o", "pipefail", "-c", script]
        script = (
            f"LC_ALL=C sort {args} -k1,1 -k4,4n {self._q(gtf)} > {self._q(str(output_file))}"
        )
        return ["bash", "-o", "pipefail", "-c", script]

    # -- 小工具 ------------------------------------------------------------ #
    @staticmethod
    def _decompressed_name(path: str) -> str:
        base = Path(path).name
        for suf in (".fa.gz", ".fasta.gz", ".fastq.gz", ".gtf.gz"):
            if base.endswith(suf):
                return base[: -len(suf)]
        return base[:-3] if base.endswith(".gz") else base

    @staticmethod
    def _gtf_stem(path: str) -> str:
        base = Path(path).name
        if base.endswith(".gtf.gz"):
            return base[: -len(".gtf.gz")]
        if base.endswith(".gtf"):
            return base[: -len(".gtf")]
        return Path(path).stem

    @staticmethod
    def _default_prefix(reads_path: str) -> str:
        base = Path(reads_path).name
        for suf in (".fa.gz", ".fasta.gz", ".fastq.gz", ".fa", ".fasta", ".fastq"):
            if base.endswith(suf):
                return base[: -len(suf)]
        return Path(reads_path).stem


# --------------------------------------------------------------------------- #
# versions.yml 兼容（与 nf-core 对齐）
# --------------------------------------------------------------------------- #
def _write_versions(outdir: str | Path, block: str, lines: list[str]) -> None:
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    with open(outdir / "versions.yml", "w") as fh:
        fh.write(f"{block}:\n")
        for k, v in lines:
            fh.write(f"    {k}: {v}\n")


def _query_version(bin_name: str) -> str:
    try:
        return subprocess.run(
            f"{bin_name} --version 2>&1",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        ).stdout.strip().splitlines()[0] if shutil.which(bin_name) else "n/a"
    except Exception:
        return "n/a"


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ultra-skill",
        description="ultra (uLTRA) native 技能驱动（自动线程 / 依赖路径 / 临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # gunzip
    pg = sub.add_parser("gunzip", help=SUBCOMMANDS["gunzip"])
    pg.add_argument("input", help="输入 .gz 文件")
    pg.add_argument("-o", "--output", help="输出文件（默认去掉 .gz 后缀）")
    pg.add_argument("--args", default="", help="透传 gzip 附加参数（可选）")
    _add_runtime_opts(pg)

    # index
    pi = sub.add_parser("index", help=SUBCOMMANDS["index"])
    pi.add_argument("--fasta", required=True, help="参考基因组 FASTA（.gz 自动先解压）")
    pi.add_argument("--gtf", required=True, help="参考注释 GTF（须已排序）")
    pi.add_argument("--outdir", required=True, help="索引输出目录")
    pi.add_argument("--args", default="--disable_infer", help="透传 uLTRA index 参数（默认 --disable_infer）")
    _add_runtime_opts(pi)

    # align
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("--reads", required=True, help="输入 reads（fasta/fastq，.gz 自动先解压）")
    pa.add_argument("--genome", required=True, help="参考基因组 FASTA")
    pa.add_argument("--index-dir", required=True, help="含 *.pickle 与 *.db 的索引目录")
    pa.add_argument("--outdir", required=True, help="输出目录")
    pa.add_argument("--prefix", default=None, help="输出前缀（默认从 reads 推断）")
    pa.add_argument("--args", default="", help="透传 uLTRA align 附加参数")
    pa.add_argument("--args2", default="", help="透传 samtools sort 附加参数")
    _add_runtime_opts(pa)

    # sort（index 前对 GTF 排序）
    ps = sub.add_parser("sort", help=SUBCOMMANDS["sort"])
    ps.add_argument("input", help="输入 GTF 文件（支持 .gtf.gz）")
    ps.add_argument("--outdir", default=".", help="输出目录（默认当前目录）")
    ps.add_argument("--prefix", default=None, help="输出前缀（默认取输入文件名 stem）")
    ps.add_argument("--args", default="", help="透传 sort 附加参数（如 --parallel 或 -S）")
    _add_runtime_opts(ps)

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
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = UltraSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = UltraSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # 版本文件（与 nf-core 对齐）
    try:
        if ns.subcommand == "gunzip":
            out = ns.output or ns.input[:-3]
            _write_versions(str(Path(out).parent), "gunzip", [("gunzip", _query_version("gzip"))])
        elif ns.subcommand == "index":
            _write_versions(ns.outdir, "ultra_index", [("ultra", _query_version("uLTRA"))])
        elif ns.subcommand == "align":
            _write_versions(ns.outdir, "ultra_align",
                            [("ultra", _query_version("uLTRA")),
                             ("samtools", _query_version("samtools"))])
        elif ns.subcommand == "sort":
            _write_versions(ns.outdir, "GNU_SORT", [("coreutils", "9.1")])
    except Exception as exc:  # 版本文件失败不阻塞主流程
        print(f"[WARN] 写 versions.yml 失败: {exc}", file=sys.stderr)

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
