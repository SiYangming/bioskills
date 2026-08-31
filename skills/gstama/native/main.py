#!/usr/bin/env python3
"""gstama native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py polyacleanup --fasta flnc.fa --outdir gstama --prefix sample
   python main.py collapse --bam aln.bam --fasta ref.fa --outdir collapse --prefix sample
   python main.py filelist --bed-dir collapse/beds --outdir filelist
   python main.py merge --filelist filelist/sample.tsv --outdir merge
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py <sub> ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/gs_tama.py + tama_polyacleanup.py：
  polyacleanup: tama_flnc_polya_cleanup.py -f <fasta> -p <prefix>，随后 gzip 三个输出
  collapse:     tama_collapse.py -s <bam> -f <fasta> -p <prefix> -b BAM [args]
  filelist:     纯 Python 扫描 *.bed 生成 <prefix>.tsv（无外部依赖）
  merge:        tama_merge.py -f <filelist> -p <prefix> -d merge_dup [args]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 skills/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "polyacleanup": "TAMA FLNC polyA 清理（tama_flnc_polya_cleanup.py）并 gzip 输出",
    "collapse": "TAMA collapse 转录本去冗余（tama_collapse.py，输入比对 BAM + 参考 FASTA）",
    "filelist": "由 collapse 产出的 bed 生成 merge 用 TSV（纯 Python，无外部依赖）",
    "merge": "TAMA merge 合并多个转录本集合（tama_merge.py）",
}

# bioconda gs-tama 提供的脚本名（tama_*.py）
_SCRIPTS = {
    "polyacleanup": "tama_flnc_polya_cleanup.py",
    "collapse": "tama_collapse.py",
    "merge": "tama_merge.py",
}


def _strip_ext(path_str: str) -> str:
    base_name = os.path.basename(path_str)
    for suf in (".bam", ".sam", ".fa", ".fasta", ".bed", ".tsv"):
        if base_name.endswith(suf):
            return base_name[: -len(suf)]
    return os.path.splitext(base_name)[0]


def _find_script(cmd: str, override: str | None) -> str:
    """解析 TAMA 脚本路径：显式 override > PATH 中的脚本名 > 脚本名本身。"""
    if override:
        return os.path.expanduser(override)
    return shutil.which(cmd) or cmd


def _filelist(bed_dir: str, cap: str, order: str | None, outdir: str,
              prefix: str | None, pattern: str) -> str:
    """纯 Python 生成 merge 用 filelist TSV（迁移自 gs_tama.py 的 subcmd_filelist）。"""
    out_path = Path(os.path.abspath(os.path.expanduser(outdir)))
    out_path.mkdir(parents=True, exist_ok=True)
    bed_dir_path = Path(os.path.abspath(os.path.expanduser(bed_dir)))
    if not prefix:
        prefix = bed_dir_path.name
    tsv_path = out_path / f"{prefix}.tsv"

    if "**" in pattern:
        rpat = pattern[3:] if pattern.startswith("**/") else pattern.lstrip("*")
        beds = sorted(bed_dir_path.rglob(rpat))
    else:
        beds = sorted(bed_dir_path.glob(pattern))
    # 过滤 macOS AppleDouble 伪文件
    beds = [b for b in beds if not b.name.startswith("._")]
    if not beds:
        raise FileNotFoundError(f"在 {bed_dir_path} 下未找到匹配 {pattern} 的 bed 文件")

    with open(tsv_path, "w") as f:
        for bed in beds:
            m = re.search(r"chunk(\d+)", bed.name)
            if m:
                n = m.group(1)
                order_str = f"{n},{n},{n}"
            elif order:
                o = str(order).strip()
                if "," in o:
                    parts = [p.strip() for p in o.split(",")]
                    order_str = ",".join(parts) if (len(parts) == 3 and all(p.isdigit() for p in parts)) else "1,1,1"
                elif o.isdigit():
                    order_str = f"{o},{o},{o}"
                else:
                    order_str = "1,1,1"
            else:
                order_str = "1,1,1"
            # 第 4 列来源标签：<bed_dir 名>:<上级目录名>:<去扩展文件名>
            source_id = f"{bed_dir_path.name}:{bed.parent.name}:{bed.stem}"
            f.write(f"{bed}\t{cap}\t{order_str}\t{source_id}\n")
    return str(tsv_path)


class GstamaSkill(base.SkillBase):
    software = "gstama"
    binary = ""  # gstama 无单一二进制，脚本按子命令解析（tama_*.py）

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建命令行（polyacleanup/collapse/merge 走 bash 链；filelist 为自调用）。"""
        if subcommand == "polyacleanup":
            return self._build_polyacleanup(kw)
        if subcommand == "collapse":
            return self._build_collapse(kw)
        if subcommand == "filelist":
            return self._build_filelist(kw)
        if subcommand == "merge":
            return self._build_merge(kw)
        raise ValueError(f"不支持的子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

    def _build_polyacleanup(self, kw: dict) -> list[str]:
        fasta = kw.get("fasta")
        if not fasta:
            raise ValueError("polyacleanup 需要输入 FASTA（--fasta）")
        outdir = Path(kw.get("outdir") or ".").resolve()
        outdir.mkdir(parents=True, exist_ok=True)
        stem = Path(str(fasta)).stem
        prefix = kw.get("prefix") or (stem + "_tama" if not stem.endswith("_tama") else stem)
        script = _find_script(_SCRIPTS["polyacleanup"], kw.get("tama_script"))
        args = shlex.split(kw.get("args") or "")
        q = shlex.quote
        cmd = (
            f"cd {q(str(outdir))} && "
            f"{q(sys.executable)} {q(script)} -f {q(str(fasta))} -p {q(prefix)} "
            f"{' '.join(map(q, args))} && "
            f"for f in {q(prefix)}.fa {q(prefix)}_polya_flnc_report.txt {q(prefix)}_tails.fa; do "
            f"[ -f \"$f\" ] && gzip -f \"$f\"; done; "
            f"echo 'gstama: 1.0.3' > versions.yml"
        )
        return ["bash", "-c", cmd]

    def _build_collapse(self, kw: dict) -> list[str]:
        bam = kw.get("bam")
        fasta = kw.get("fasta")
        if not bam or not fasta:
            raise ValueError("collapse 需要输入 --bam 与 --fasta（参考基因组）")
        outdir = Path(kw.get("outdir") or ".").resolve()
        outdir.mkdir(parents=True, exist_ok=True)
        prefix = kw.get("prefix") or _strip_ext(str(bam))
        script = _find_script(_SCRIPTS["collapse"], kw.get("tama_collapse_script"))
        args = shlex.split(kw.get("args") or "")
        input_flag = "-b BAM" if kw.get("bam_input", True) else "-b SAM"
        q = shlex.quote
        env_setup = ""
        if kw.get("samtools_bin"):
            sb = os.path.expanduser(str(kw["samtools_bin"]))
            env_setup = f"export SAMTOOLS_BIN={q(sb)}; export PATH={q(os.path.dirname(sb))}:$PATH; "
        cmd = (
            f"cd {q(str(outdir))} && {env_setup}"
            f"{q(sys.executable)} {q(script)} -s {q(str(bam))} -f {q(str(fasta))} "
            f"-p {q(prefix)} {input_flag} {' '.join(map(q, args))} && "
            f"echo 'gstama: 1.0.3' > versions.yml"
        )
        return ["bash", "-c", cmd]

    def _build_filelist(self, kw: dict) -> list[str]:
        """filelist 为纯 Python 逻辑，返回自调用 CLI 命令（供 --dry-run / 内省）。"""
        if not kw.get("bed_dir") or not kw.get("outdir"):
            raise ValueError("filelist 需要 --bed-dir 与 --outdir")
        cmd = [sys.executable, str(_HERE / "main.py"), "filelist"]
        for flag, key in (("--bed-dir", "bed_dir"), ("--cap", "cap"), ("--order", "order"),
                          ("--outdir", "outdir"), ("--prefix", "prefix"), ("--pattern", "pattern")):
            if kw.get(key) is not None:
                cmd += [flag, str(kw[key])]
        return cmd

    def _build_merge(self, kw: dict) -> list[str]:
        filelist = kw.get("filelist")
        if not filelist:
            raise ValueError("merge 需要输入 filelist TSV（--filelist）")
        outdir = Path(kw.get("outdir") or ".").resolve()
        outdir.mkdir(parents=True, exist_ok=True)
        prefix = kw.get("prefix") or _strip_ext(str(filelist))
        script = _find_script(_SCRIPTS["merge"], kw.get("tama_merge_script"))
        args = shlex.split(kw.get("args") or "")
        q = shlex.quote
        cmd = (
            f"cd {q(str(outdir))} && "
            f"if [ ! -s {q(str(filelist))} ]; then "
            f"echo 'gstama_merge: skipped (no filelist)' > versions.yml; "
            f"else {q(sys.executable)} {q(script)} -f {q(str(filelist))} "
            f"-p {q(prefix)} -d merge_dup {' '.join(map(q, args))} && "
            f"echo 'gstama: 1.0.3' > versions.yml; fi"
        )
        return ["bash", "-c", cmd]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gstama-skill",
        description="gstama native 技能驱动（polyacleanup / collapse / filelist / merge）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # polyacleanup
    pp = sub.add_parser("polyacleanup", help=SUBCOMMANDS["polyacleanup"])
    pp.add_argument("--fasta", required=True, help="输入 FLNC FASTA（如 bamtools convert 输出）")
    pp.add_argument("--outdir", default=".", help="输出目录")
    pp.add_argument("--prefix", default=None, help="输出前缀（默认 <fasta 名>_tama）")
    pp.add_argument("--args", default="", help="透传 tama_flnc_polya_cleanup.py 的附加参数")
    pp.add_argument("--tama-script", default=None, help="tama_flnc_polya_cleanup.py 路径（默认 PATH）")
    _add_runtime_opts(pp)

    # collapse
    pc = sub.add_parser("collapse", help=SUBCOMMANDS["collapse"])
    pc.add_argument("--bam", required=True, help="输入比对 BAM（建议已排序）")
    pc.add_argument("--fasta", required=True, help="参考基因组 FASTA")
    pc.add_argument("--outdir", default=".", help="输出目录")
    pc.add_argument("--prefix", default=None, help="输出前缀（默认从 BAM 文件名推断）")
    pc.add_argument("--args", default="", help="透传 tama_collapse.py 的附加参数（如 -x no_cap -a 100 ...）")
    pc.add_argument("--tama-collapse-script", default=None, help="tama_collapse.py 路径（默认 PATH）")
    pc.add_argument("--samtools-bin", default=None, help="samtools 可执行路径（注入 PATH 供 tama_collapse.py 调用）")
    pc.add_argument("--no-bam-input", action="store_true", help="输入为 SAM 时使用 -b SAM")
    _add_runtime_opts(pc)

    # filelist
    pf = sub.add_parser("filelist", help=SUBCOMMANDS["filelist"])
    pf.add_argument("--bed-dir", required=True, help="包含 collapse 产出 *.bed 的目录")
    pf.add_argument("--cap", choices=("capped", "no_cap"), default="no_cap", help="cap 列（Iso-Seq 默认 no_cap）")
    pf.add_argument("--order", default=None, help="order 列（三元 'start,junction,end'）")
    pf.add_argument("--outdir", required=True, help="输出目录")
    pf.add_argument("--prefix", default=None, help="输出前缀（默认取 bed 目录名）")
    pf.add_argument("--pattern", default="*.bed", help="bed 匹配模式（默认 *.bed，支持 **/ 递归）")
    _add_runtime_opts(pf)

    # merge
    pm = sub.add_parser("merge", help=SUBCOMMANDS["merge"])
    pm.add_argument("--filelist", required=True, help="filelist 子命令生成的 TSV")
    pm.add_argument("--outdir", default=".", help="输出目录")
    pm.add_argument("--prefix", default=None, help="输出前缀（默认从 filelist 文件名推断）")
    pm.add_argument("--args", default="", help="透传 tama_merge.py 的附加参数（如 -a 100 -z 100 -m 20）")
    pm.add_argument("--tama-merge-script", default=None, help="tama_merge.py 路径（默认 PATH）")
    _add_runtime_opts(pm)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GstamaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GstamaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    # filelist 为纯 Python 逻辑，直接在本进程执行（不 shell out）
    if ns.subcommand == "filelist":
        try:
            tsv = _filelist(kw["bed_dir"], kw.get("cap", "no_cap"), kw.get("order"),
                            kw["outdir"], kw.get("prefix"), kw.get("pattern", "*.bed"))
        except (FileNotFoundError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 1
        outdir = Path(os.path.abspath(os.path.expanduser(kw["outdir"])))
        outdir.mkdir(parents=True, exist_ok=True)
        (outdir / "versions.yml").write_text("GSTAMA_FILELIST:\n    python: built-in\n")
        print(f"生成 filelist: {tsv}")
        return 0

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
