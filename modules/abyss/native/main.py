#!/usr/bin/env python3
"""abyss native 标准入口驱动（ABySS 1.9.0）。

ABySS（Assembly By Short Sequences）是基于 de Bruijn Graph 的并行化基因组组装器，
本驱动覆盖其 8 个核心程序：
  1. assemble        abyss-pe [np=<N>] j=<J> k=<K> [name=<name>] [lib=<lib>] [<key=value>...]
  2. map             abyss-map -j <J> [-l <L>] <reads1> [<reads2>] <ref.fa>
  3. fixmate         abyss-fixmate [-l <L>] -h <hist>
  4. distance-est    DistanceEst [--dot] -j <J> -k <K> [-l <L>] [-s <S>] [-n <N>] -o <out> <hist>
  5. scaffold        abyss-scaffold -k <K> [-s <S>] [-n <N>] -g <graph> <assembly.fa> <dist.dot>
  6. path-consensus  PathConsensus -k <K> [-p <P>] -s <scaffolds> -g <adj> -o <path> <contigs...>
  7. merge-contigs   MergeContigs -k <K> -o <out> <contigs|-> <adj> <path>
  8. path-overlap    PathOverlap [--overlap] [--dot] -k <K> <adj> <path>

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py assemble --kmer 51 --name E_coli --lib "pe1 mp=mp1" \
       --extra-args 'pe1="fragment.1.fastq fragment.2.fastq" mp1="jumping.1.fastq jumping.2.fastq"'
   python main.py map --reads1 jumping.1.fastq --reads2 jumping.2.fastq \
       --ref E_coli-6.fa --kmer 51 --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程：优先级为「显式 --threads > meta optimization.per_subcommand_threads > default_cpus」；
assemble 透传 `j=`（另有 `--np` 透传 MPI 进程数 `np=`），map / distance-est 透传 `-j`。
`--tmpdir` 经进程环境变量 `TMPDIR` 注入（ABySS 无自身 tmp 选项）。

前置：ABySS 程序在 PATH（bioconda abyss=1.9.0 / brew install abyss / 官方源码编译，见
README「环境安装」与 native/install.sh）。版本说明：本模块登记文档教学版 1.9.0，上游最新
为 2.3.10（bioconda / nf-core abyss/abysspe pin）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "assemble": "abyss-pe 组装（abyss-pe [np=] j= k= name= lib= pe1=... mp1=...）",
    "map": "读段比对到 contigs（abyss-map -j -l reads... ref）",
    "fixmate": "修正 mate 并输出 histogram（abyss-fixmate -l -h）",
    "distance-est": "估计 mate 方向/距离（DistanceEst --dot -j -k -l -s -n -o）",
    "scaffold": "独立 scaffolding（abyss-scaffold -k -s -n -g assembly dist）",
    "path-consensus": "path 一致性拆分（PathConsensus -k -p -s -g -o contigs...）",
    "merge-contigs": "合并 contigs（MergeContigs -k -o contigs adj path）",
    "path-overlap": "输出 path 重叠 dot（PathOverlap --overlap --dot -k adj path）",
}

# 子命令 → 真实可执行名
_BINARIES = {
    "assemble": "abyss-pe",
    "map": "abyss-map",
    "fixmate": "abyss-fixmate",
    "distance-est": "DistanceEst",
    "scaffold": "abyss-scaffold",
    "path-consensus": "PathConsensus",
    "merge-contigs": "MergeContigs",
    "path-overlap": "PathOverlap",
}


class AbyssSkill(base.SkillBase):
    software = "abyss"
    binary = "abyss-pe"

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令惰性解析所需二进制（shutil.which）。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 ABySS 并把其 bin 目录加入 PATH"
                f"（bioconda: mamba create -n abyss-native -c conda-forge -c bioconda "
                f"abyss=1.9.0；或 brew install abyss；官方源码见 "
                f"https://github.com/bcgsc/abyss 与 README「环境安装」）。"
            )
        return path

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def run_env(self) -> dict[str, str]:
        """渲染运行环境：meta env_vars + 以 self.tmpdir 覆盖 TMPDIR（支持 --tmpdir）。"""
        env = dict(self.env_vars)
        env["TMPDIR"] = self.tmpdir
        return env

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """8 个子命令：构造 ABySS 命令行（随后由 run() 真实执行）。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(
                f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "assemble":
            return self._build_assemble(bin_path, **kw)
        if subcommand == "map":
            return self._build_map(bin_path, **kw)
        if subcommand == "fixmate":
            return self._build_fixmate(bin_path, **kw)
        if subcommand == "distance-est":
            return self._build_distance(bin_path, **kw)
        if subcommand == "scaffold":
            return self._build_scaffold(bin_path, **kw)
        if subcommand == "path-consensus":
            return self._build_path_consensus(bin_path, **kw)
        if subcommand == "merge-contigs":
            return self._build_merge_contigs(bin_path, **kw)
        return self._build_path_overlap(bin_path, **kw)

    def run(self, subcommand: str, **kwargs):
        """构建并真实执行命令（TMPDIR/线程按运行期覆盖注入）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.run_env(), check=False)

    # -- assemble ---------------------------------------------------------- #
    def _build_assemble(self, bin_path: str, **kw) -> list[str]:
        kmer = kw.get("kmer")
        if kmer is None:
            raise RuntimeError("assemble 需要 --kmer（abyss-pe k=<K>）")
        threads = self._effective_threads("assemble", kw.get("threads"))
        cmd = [bin_path]
        if kw.get("np"):
            cmd.append(f"np={int(kw['np'])}")
        cmd.append(f"j={threads}")
        cmd.append(f"k={int(kmer)}")
        if kw.get("name"):
            cmd.append(f"name={kw['name']}")
        if kw.get("lib"):
            cmd.append(f"lib={kw['lib']}")
        if kw.get("extra_args"):
            cmd += str(kw["extra_args"]).split()
        return cmd

    # -- map --------------------------------------------------------------- #
    def _build_map(self, bin_path: str, **kw) -> list[str]:
        reads1 = kw.get("reads1")
        ref = kw.get("ref")
        if not reads1:
            raise RuntimeError("map 需要 --reads1（读段 1/SE reads）")
        if not ref:
            raise RuntimeError("map 需要 --ref（参考/contigs FASTA，位置参数）")
        threads = self._effective_threads("map", kw.get("threads"))
        cmd = [bin_path, "-j", str(threads)]
        if kw.get("kmer") is not None:
            cmd += ["-l", str(int(kw["kmer"]))]
        cmd.append(self._abspath(reads1))
        if kw.get("reads2"):
            cmd.append(self._abspath(kw["reads2"]))
        cmd.append(self._abspath(ref))
        return cmd

    # -- fixmate ----------------------------------------------------------- #
    def _build_fixmate(self, bin_path: str, **kw) -> list[str]:
        hist = kw.get("hist")
        if not hist:
            raise RuntimeError("fixmate 需要 --hist（-h mate histogram）")
        cmd = [bin_path]
        if kw.get("kmer") is not None:
            cmd += ["-l", str(int(kw["kmer"]))]
        cmd += ["-h", str(hist)]
        return cmd

    # -- distance-est ------------------------------------------------------ #
    def _build_distance(self, bin_path: str, **kw) -> list[str]:
        hist = kw.get("hist")
        out = kw.get("out")
        if not hist:
            raise RuntimeError("distance-est 需要 --hist（位置参数 .hist）")
        if not out:
            raise RuntimeError("distance-est 需要 --out（-o .dist.dot）")
        threads = self._effective_threads("distance-est", kw.get("threads"))
        cmd = [bin_path]
        if kw.get("dot"):
            cmd.append("--dot")
        cmd += ["-j", str(threads)]
        if kw.get("kmer") is not None:
            cmd += ["-k", str(int(kw["kmer"]))]
        if kw.get("length") is not None:
            cmd += ["-l", str(int(kw["length"]))]
        if kw.get("size") is not None:
            cmd += ["-s", str(int(kw["size"]))]
        if kw.get("num") is not None:
            cmd += ["-n", str(int(kw["num"]))]
        cmd += ["-o", str(out), str(hist)]
        return cmd

    # -- scaffold ---------------------------------------------------------- #
    def _build_scaffold(self, bin_path: str, **kw) -> list[str]:
        graph = kw.get("graph")
        assembly = kw.get("assembly")
        dist = kw.get("dist")
        if not graph:
            raise RuntimeError("scaffold 需要 --graph（-g 图文件）")
        if not assembly:
            raise RuntimeError("scaffold 需要 --assembly（contigs 位置参数 1）")
        if not dist:
            raise RuntimeError("scaffold 需要 --dist（dist.dot 位置参数 2）")
        cmd = [bin_path]
        if kw.get("kmer") is not None:
            cmd += ["-k", str(int(kw["kmer"]))]
        if kw.get("size") is not None:
            cmd += ["-s", str(int(kw["size"]))]
        if kw.get("num") is not None:
            cmd += ["-n", str(int(kw["num"]))]
        cmd += ["-g", str(graph), self._abspath(assembly), self._abspath(dist)]
        return cmd

    # -- path-consensus ---------------------------------------------------- #
    def _build_path_consensus(self, bin_path: str, **kw) -> list[str]:
        scaffolds = kw.get("scaffolds")
        graph = kw.get("graph")
        output_path = kw.get("output_path")
        contigs = kw.get("contigs")
        if not scaffolds:
            raise RuntimeError("path-consensus 需要 --scaffolds（-s 输出 scaffolds）")
        if not graph:
            raise RuntimeError("path-consensus 需要 --graph（-g adj 文件）")
        if not output_path:
            raise RuntimeError("path-consensus 需要 --output-path（-o 输出 path）")
        if not contigs:
            raise RuntimeError("path-consensus 需要 --contigs（contigs 文件，可多个）")
        contigs = list(contigs) if isinstance(contigs, (list, tuple)) else [contigs]
        cmd = [bin_path]
        if kw.get("kmer") is not None:
            cmd += ["-k", str(int(kw["kmer"]))]
        if kw.get("percent") is not None:
            cmd += ["-p", str(kw["percent"])]
        cmd += ["-s", self._abspath(scaffolds), "-g", self._abspath(graph),
                "-o", self._abspath(output_path)]
        cmd += [self._abspath(c) for c in contigs]
        return cmd

    # -- merge-contigs ----------------------------------------------------- #
    def _build_merge_contigs(self, bin_path: str, **kw) -> list[str]:
        out = kw.get("out")
        adj = kw.get("adj")
        path_file = kw.get("path_file")
        contigs = kw.get("contigs")
        if not out:
            raise RuntimeError("merge-contigs 需要 --out（-o 输出）")
        if not adj:
            raise RuntimeError("merge-contigs 需要 --adj（.adj 文件）")
        if not path_file:
            raise RuntimeError("merge-contigs 需要 --path-file（.path 文件）")
        if not contigs:
            raise RuntimeError("merge-contigs 需要 --contigs（contigs 文件；stdin 用 '-'）")
        contigs_v = contigs[0] if isinstance(contigs, (list, tuple)) else contigs
        cmd = [bin_path]
        if kw.get("kmer") is not None:
            cmd += ["-k", str(int(kw["kmer"]))]
        cmd += ["-o", self._abspath(out), str(contigs_v),
                self._abspath(adj), self._abspath(path_file)]
        return cmd

    # -- path-overlap ------------------------------------------------------ #
    def _build_path_overlap(self, bin_path: str, **kw) -> list[str]:
        adj = kw.get("adj")
        path_file = kw.get("path_file")
        if not adj:
            raise RuntimeError("path-overlap 需要 --adj（.adj 文件）")
        if not path_file:
            raise RuntimeError("path-overlap 需要 --path-file（.path 文件）")
        cmd = [bin_path]
        if kw.get("overlap"):
            cmd.append("--overlap")
        if kw.get("dot"):
            cmd.append("--dot")
        if kw.get("kmer") is not None:
            cmd += ["-k", str(int(kw["kmer"]))]
        cmd += [self._abspath(adj), self._abspath(path_file)]
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int,
                   help="覆盖默认线程数（assemble 透传 j=；map/distance-est 透传 -j）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（经 TMPDIR 注入）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="abyss-skill",
        description="ABySS native 技能驱动（abyss-pe 组装 + 独立 scaffolding 链路）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("assemble", help=SUBCOMMANDS["assemble"])
    pa.add_argument("--kmer", "-k", type=int, required=True, help="k-mer 长度（k=，如 51）")
    pa.add_argument("--name", help="name= 输出前缀/库名（如 E_coli）")
    pa.add_argument("--lib", help="lib= 库定义（如 'pe1 mp=mp1'）")
    pa.add_argument("--np", type=int, help="np= MPI 进程数（并行组装，需 mpd）")
    pa.add_argument("--extra-args",
                    help="透传额外 key=value（如 pe1=\"f1 f2\" mp1=\"j1 j2\"）")
    _add_runtime_opts(pa)

    pm = sub.add_parser("map", help=SUBCOMMANDS["map"])
    pm.add_argument("--reads1", required=True, help="读段 1（或 SE reads）")
    pm.add_argument("--reads2", help="读段 2（PE，可省略）")
    pm.add_argument("--ref", required=True, help="参考/contigs FASTA（位置参数）")
    pm.add_argument("--kmer", "-l", type=int, help="k-mer 长度（-l，如 51）")
    _add_runtime_opts(pm)

    pf = sub.add_parser("fixmate", help=SUBCOMMANDS["fixmate"])
    # 注：官方 fixmate 的 histogram 参数为 -h，但 argparse 保留 -h 作 help，
    # 故此处仅暴露长选项 --hist（内部透传 -h）。
    pf.add_argument("--hist", required=True, help="mate histogram 文件（透传 -h）")
    pf.add_argument("--kmer", "-l", type=int, help="k-mer 长度（-l）")
    _add_runtime_opts(pf)

    pde = sub.add_parser("distance-est", help=SUBCOMMANDS["distance-est"])
    pde.add_argument("--hist", required=True, help="位置参数 .hist")
    pde.add_argument("--kmer", "-k", type=int, help="k-mer 长度（-k）")
    pde.add_argument("--length", "-l", type=int, help="读段长度（-l）")
    pde.add_argument("--size", "-s", type=int, help="距离阈值（-s）")
    pde.add_argument("--num", "-n", type=int, help="命中数阈值（-n）")
    pde.add_argument("--out", "-o", required=True, help="输出 .dist.dot（-o）")
    pde.add_argument("--dot", action="store_true", help="--dot 输出 dot 图")
    _add_runtime_opts(pde)

    psc = sub.add_parser("scaffold", help=SUBCOMMANDS["scaffold"])
    psc.add_argument("--graph", "-g", required=True, help="图文件（-g，如 E_coli-6.path.dot）")
    psc.add_argument("--assembly", required=True, help="contigs 位置参数 1（如 E_coli-6.fa）")
    psc.add_argument("--dist", required=True, help="dist.dot 位置参数 2（如 mp1-6.dist.dot）")
    psc.add_argument("--kmer", "-k", type=int, help="k-mer 长度（-k）")
    psc.add_argument("--size", "-s", type=int, help="距离阈值（-s）")
    psc.add_argument("--num", "-n", type=int, help="命中数阈值（-n）")
    _add_runtime_opts(psc)

    ppc = sub.add_parser("path-consensus", help=SUBCOMMANDS["path-consensus"])
    ppc.add_argument("--scaffolds", "-s", required=True, help="输出 scaffolds（-s）")
    ppc.add_argument("--graph", "-g", required=True, help="adj 文件（-g）")
    ppc.add_argument("--output-path", "-o", required=True, help="输出 path（-o）")
    ppc.add_argument("--contigs", nargs="+", required=True, help="contigs 文件（可多个）")
    ppc.add_argument("--kmer", "-k", type=int, help="k-mer 长度（-k）")
    ppc.add_argument("--percent", "-p", type=float, help="置信度百分比（-p，如 0.9）")
    _add_runtime_opts(ppc)

    pmc = sub.add_parser("merge-contigs", help=SUBCOMMANDS["merge-contigs"])
    pmc.add_argument("--out", "-o", required=True, help="输出（-o，如 E_coli-8.fa）")
    pmc.add_argument("--contigs", required=True, help="contigs 文件（stdin 用 '-'）")
    pmc.add_argument("--adj", required=True, help="adj 文件（.adj）")
    pmc.add_argument("--path-file", required=True, help="path 文件（.path）")
    pmc.add_argument("--kmer", "-k", type=int, help="k-mer 长度（-k）")
    _add_runtime_opts(pmc)

    ppo = sub.add_parser("path-overlap", help=SUBCOMMANDS["path-overlap"])
    ppo.add_argument("--adj", required=True, help="adj 文件（.adj）")
    ppo.add_argument("--path-file", required=True, help="path 文件（.path）")
    ppo.add_argument("--kmer", "-k", type=int, help="k-mer 长度（-k）")
    ppo.add_argument("--overlap", action="store_true", help="--overlap 输出重叠")
    ppo.add_argument("--dot", action="store_true", help="--dot 输出 dot")
    _add_runtime_opts(ppo)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if args and args[0] == "--":
        args = args[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        skill = AbyssSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AbyssSkill()
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
