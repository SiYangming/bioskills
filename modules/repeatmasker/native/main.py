#!/usr/bin/env python3
"""repeatmasker native 标准入口驱动。

RepeatMasker（www.repeatmasker.org，上游 Dfam-consortium）是屏蔽并注释基因组中已知
重复序列（转座子 / 简单串联重复 / 低复杂度区）的行业标准工具：基于 RepBase / Dfam
重复库、以 RMBlast（rmblastn）为默认搜索引擎，输出 N 屏蔽序列（*.masked）与重复注释
（*.out / *.tbl / *.out.gff）。运行依赖（rmblast / hmmer / trf / famdb 等）由 bioconda
repeatmasker 包一并装入，本驱动不单独管理。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py query_species_tree                        # 列出库内可用 -species 物种树
   python main.py mask genome.fasta -species fungi -dir rm_fungi --threads 4
   python main.py mask genome.fasta -lib consensi.fa -dir rm_ab -gff --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

子命令语义：
- mask                = 包装 RepeatMasker：-pa <线程> -e <引擎> [-species X | -lib lib.fa]
                      [-dir out] [-gff] <genome.fasta>。ncbi 与 rmblast 均为 RMBlast/rmblastn
                      引擎别名（RepeatMasker 内部归一化），默认 -e ncbi。
- query_species_tree  = 包装 RepeatMasker 发行内 util/queryRepeatDatabase.pl -tree：把重复库
                      可用 -species 物种树打印到 stdout。注意：RepeatMasker >= 4.2 改用
                      FamDB/Dfam 后该脚本不再随发行提供，届时查物种请用 famdb 工具。
所有子命令自动注入临时目录（--tmpdir / TMPDIR env）。
"""
from __future__ import annotations

import argparse
import json
import shutil
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
    "mask": "RepeatMasker：屏蔽/注释基因组已知重复（-species 走 RepBase/Dfam 库 或 -lib 自定义库，-gff 出 GFF3）",
    "query_species_tree": "RepeatMasker util/queryRepeatDatabase.pl -tree：列出重复库可用 -species 物种树（stdout）",
}

# RepeatMasker 发行内 util 脚本名（经典 RepBase 安装随发行提供）
_RM_UTIL_SCRIPT = "queryRepeatDatabase.pl"


class RepeatMaskerSkill(base.SkillBase):
    software = "repeatmasker"
    binary = "RepeatMasker"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/repeatmasker/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_util_script(self, name: str) -> str:
        """解析 RepeatMasker 发行内的 util 脚本（如 queryRepeatDatabase.pl）。

        查找顺序：
        1. PATH 直查（bioconda 会把发行内 util/* 全部软链进 bin/；tarball 手装后也可自行加 PATH）；
        2. 沿 RepeatMasker 可执行文件反查安装根，再探测常见布局：
           <root>/util/<name>（tarball：RepeatMasker/ 内含 RepeatMasker 与 util/）；
           以及 <bin 上层>/RepeatMasker/util/<name>（脚本与二进制分置时的兜底）。
        """
        hit = shutil.which(name)
        if hit:
            return hit
        try:
            # conda 布局下 RepeatMasker 是指向 <prefix>/share/RepeatMasker/RepeatMasker 的软链，
            # resolve() 后其父目录即安装根（内含 util/）。
            rm_bin = Path(self._resolve_binary()).resolve()
        except RuntimeError:
            rm_bin = None
        if rm_bin is not None:
            for root in (rm_bin.parent, rm_bin.parent.parent, rm_bin.parent.parent.parent):
                util = root / "util" / name
                if util.is_file():
                    return str(util)
                nested = root / "RepeatMasker" / "util" / name
                if nested.is_file():
                    return str(nested)
        raise RuntimeError(
            f"未找到 RepeatMasker 配套脚本 '{name}'（即 RepeatMasker 发行目录 util/{name}）。"
            "请确认已安装 RepeatMasker（conda repeatmasker 或官方 tarball 解压到 PATH）；"
            "提示：RepeatMasker >= 4.2 改用 FamDB/Dfam 后该经典脚本不再随发行提供，"
            "缺失时查询 -species 可用名请用 famdb 工具（见 README「实战示例 §3」）。"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 RepeatMasker 命令行。"""
        if subcommand == "mask":
            genome_fasta = kw.get("genome_fasta")
            if not genome_fasta:
                raise RuntimeError("mask 需要 genome_fasta（基因组 FASTA，位置参数）")
            species = kw.get("species")
            lib = kw.get("lib")
            if not species and not lib:
                raise RuntimeError(
                    "mask 需要 -species（库内物种名）或 -lib（自定义重复库）至少一项："
                    "RepeatMasker 4.2.x 不带默认重复库，裸跑无库会直接失败。"
                )
            binary = self._resolve_binary()
            threads = self._effective_threads(subcommand, kw.get("threads"))
            # RepeatMasker [-options] <seqfiles...>：选项在前、输入文件在后
            cmd: list[str] = [binary, "-pa", str(threads)]
            engine = kw.get("engine") or "ncbi"
            if engine:
                cmd += ["-e", str(engine)]
            dir_ = kw.get("dir")
            if dir_:
                cmd += ["-dir", str(dir_)]
            if species:
                cmd += ["-species", str(species)]
            if lib:
                cmd += ["-lib", str(lib)]
            if kw.get("gff"):
                cmd += ["-gff"]
            # 高级透传（慎用；如 -xsmall -cutoff 3.7 -no_is 等常用项），置于输入文件之前
            extra = kw.get("extra_args")
            if extra:
                cmd += str(extra).split()
            cmd += [str(genome_fasta)]
        elif subcommand == "query_species_tree":
            # RepeatMasker util/queryRepeatDatabase.pl -tree：无额外参数，物种树走 stdout
            script = self._resolve_util_script(_RM_UTIL_SCRIPT)
            cmd = [script, "-tree"]
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="repeatmasker-skill",
        description="repeatmasker native 技能驱动（自动线程/TMPDIR；重复序列屏蔽与注释）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # mask: RepeatMasker -pa N -e <engine> [-dir <out>] [-species X | -lib lib.fa] [-gff] <genome.fasta>
    pm = sub.add_parser("mask", help=SUBCOMMANDS["mask"])
    pm.add_argument("genome_fasta", help="基因组 FASTA（位置参数）")
    pm.add_argument("-species", "--species",
                    help="重复库内物种/分类群名（先跑 query_species_tree 查可用名；与 -lib 至少一项）")
    pm.add_argument("-lib", "--lib", help="自定义重复库 FASTA（如 RepeatModeler 的 consensi.fa；与 -species 至少一项）")
    pm.add_argument("-dir", "--dir", help="输出目录（默认当前目录；多样本批量请分目录）")
    pm.add_argument("-e", "--engine", default="ncbi",
                    help="搜索引擎（默认 ncbi；ncbi/rmblast 均为 RMBlast/rmblastn 引擎别名）")
    pm.add_argument("-gff", "--gff", action="store_true", help="追加 GFF3 注释（<name>.out.gff）")
    pm.add_argument("--extra-args", dest="extra_args",
                    help="透传给 RepeatMasker 的额外参数（如 -xsmall -cutoff 3.7，高级用法，慎用）")
    _add_runtime_opts(pm)

    # query_species_tree: RepeatMasker util/queryRepeatDatabase.pl -tree（stdout 物种树）
    pq = sub.add_parser("query_species_tree", help=SUBCOMMANDS["query_species_tree"])
    _add_runtime_opts(pq)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（mask 注入 -pa；query_species_tree 不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = RepeatMaskerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RepeatMaskerSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # 非捕获类（无 stdout）的子命令直接继承退出码
    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        # query_species_tree 的物种树 / mask 的少量 stdout 直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
