#!/usr/bin/env python3
"""clustalw native 标准入口驱动。

ClustalW 2.1 — 经典多序列比对（渐进式比对算法），适用于核酸与蛋白质序列；可产出比对
结果与引导树/系统发育树（NJ/UPGMA，支持 bootstrap）。ClustalW 为单线程程序。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align -infile=seqs.fasta -outfile=aln.fasta -output=FASTA -type=PROTEIN
   python main.py tree -infile=aln.fasta -outfile=tree.ph -outputtree=phylip
   python main.py profile -profile1=a.aln -profile2=b.aln -outfile=merged.aln -output=CLUSTAL
   python main.py help
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对照 clustalw man page；选项关键字大小写不敏感，本驱动用小写）：
  align    clustalw -infile=<in> -outfile=<out> -output=<fmt> -type=<PROTEIN|DNA> -align
                    [-quicktree] [-matrix=] [-gapopen=] [-gapext=] [-outorder=] [-quiet] [-stats=] [-newtree=]
  tree     clustalw -infile=<in> -tree -outfile=<out> [-newtree=] [-outputtree=nj|phylip|dist|nexus]
                    [-clustering=NJ|UPGMA] [-bootstrap=n] [-quiet]
  profile  clustalw -profile1=<a> -profile2=<b> -profile -outfile=<out> -output=<fmt> [-usetree1=] [-usetree2=]
  help     clustalw -help
注意：ClustalW 无多线程选项，--threads 被接受但不注入 argv（仅接口占位，线程优先级
仍按 --threads > per_subcommand_threads > default_cpus 计算）。
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

SUBCOMMANDS = {
    "align": "多序列比对：clustalw -infile=<in> -outfile=<out> -output=<fmt> -align",
    "tree": "系统发育树：clustalw -infile=<in> -tree -outfile=<out> [-outputtree=]",
    "profile": "比对合并（profile alignment）：clustalw -profile1=<a> -profile2=<b> -profile",
    "help": "打印 ClustalW 帮助（clustalw -help）",
}

_OUTPUT_FORMATS = ("CLUSTAL", "FASTA", "PHYLIP", "NEXUS", "PIR", "GDE", "GCG")
_OUTPUT_TREES = ("nj", "phylip", "dist", "nexus")
_CLUSTERING = ("NJ", "UPGMA")


class ClustalwSkill(base.SkillBase):
    software = "clustalw"
    binary = "clustalw"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        注意：ClustalW 单线程，此值仅作接口占位（不注入 argv）。
        """
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 clustalw 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_binary()

        if subcommand == "help":
            return [bin_path, "-help"]
        if subcommand == "align":
            return self._build_align(bin_path, **kw)
        if subcommand == "tree":
            return self._build_tree(bin_path, **kw)
        return self._build_profile(bin_path, **kw)

    @staticmethod
    def _opt(name: str, value) -> str:
        """构造 clustalw 的 -name=value 选项。"""
        return f"-{name}={value}"

    def _validate_output(self, fmt: str | None) -> None:
        if fmt and fmt.upper() not in _OUTPUT_FORMATS:
            raise RuntimeError(
                f"output_format 仅支持 {'/'.join(_OUTPUT_FORMATS)}（收到: {fmt}）"
            )

    def _common(self, kw: dict) -> list[str]:
        """align/tree/profile 共用的通用参数。"""
        cmd: list[str] = []
        if kw.get("seqtype"):
            cmd.append(self._opt("type", str(kw["seqtype"]).upper()))
        if kw.get("quiet"):
            cmd.append("-quiet")
        return cmd

    # -- align ------------------------------------------------------------- #
    def _build_align(self, bin_path: str, **kw) -> list[str]:
        infile = kw.get("infile")
        if not infile:
            raise RuntimeError("align 缺少必填参数 infile（-infile= 输入序列文件）")
        fmt = kw.get("output_format")
        self._validate_output(fmt)

        cmd = [bin_path, self._opt("infile", infile)]
        if kw.get("outfile"):
            cmd.append(self._opt("outfile", kw["outfile"]))
        if fmt:
            cmd.append(self._opt("output", fmt.upper()))
        cmd += self._common(kw)
        if kw.get("quicktree"):
            cmd.append("-quicktree")
        if kw.get("matrix"):
            cmd.append(self._opt("matrix", kw["matrix"]))
        if kw.get("gapopen") is not None:
            cmd.append(self._opt("gapopen", kw["gapopen"]))
        if kw.get("gapext") is not None:
            cmd.append(self._opt("gapext", kw["gapext"]))
        if kw.get("outorder"):
            cmd.append(self._opt("outorder", str(kw["outorder"]).upper()))
        if kw.get("stats"):
            cmd.append(self._opt("stats", kw["stats"]))
        if kw.get("newtree"):
            cmd.append(self._opt("newtree", kw["newtree"]))
        cmd.append("-align")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- tree -------------------------------------------------------------- #
    def _build_tree(self, bin_path: str, **kw) -> list[str]:
        infile = kw.get("infile")
        if not infile:
            raise RuntimeError("tree 缺少必填参数 infile（-infile= 输入比对文件）")

        cmd = [bin_path, self._opt("infile", infile)]
        if kw.get("outfile"):
            cmd.append(self._opt("outfile", kw["outfile"]))
        if kw.get("newtree"):
            cmd.append(self._opt("newtree", kw["newtree"]))
        if kw.get("outputtree"):
            ot = str(kw["outputtree"])
            if ot.lower() not in _OUTPUT_TREES:
                raise RuntimeError(f"outputtree 仅支持 {'/'.join(_OUTPUT_TREES)}（收到: {ot}）")
            cmd.append(self._opt("outputtree", ot.lower()))
        if kw.get("clustering"):
            cl = str(kw["clustering"]).upper()
            if cl not in _CLUSTERING:
                raise RuntimeError(f"clustering 仅支持 {'/'.join(_CLUSTERING)}（收到: {cl}）")
            cmd.append(self._opt("clustering", cl))
        cmd += self._common(kw)
        if kw.get("bootstrap") is not None:
            cmd.append(self._opt("bootstrap", kw["bootstrap"]))
            # -bootstrap=n 本身即「构建 bootstrap NJ 树」动词，无需再给 -tree
        else:
            cmd.append("-tree")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- profile ----------------------------------------------------------- #
    def _build_profile(self, bin_path: str, **kw) -> list[str]:
        p1 = kw.get("profile1")
        p2 = kw.get("profile2")
        if not p1:
            raise RuntimeError("profile 缺少必填参数 profile1（-profile1= 第一组比对）")
        if not p2:
            raise RuntimeError("profile 缺少必填参数 profile2（-profile2= 第二组比对）")
        fmt = kw.get("output_format")
        self._validate_output(fmt)

        cmd = [bin_path, self._opt("profile1", p1), self._opt("profile2", p2)]
        if kw.get("outfile"):
            cmd.append(self._opt("outfile", kw["outfile"]))
        if fmt:
            cmd.append(self._opt("output", fmt.upper()))
        cmd += self._common(kw)
        if kw.get("usetree1"):
            cmd.append(self._opt("usetree1", kw["usetree1"]))
        if kw.get("usetree2"):
            cmd.append(self._opt("usetree2", kw["usetree2"]))
        cmd.append("-profile")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（真实执行，找不到二进制抛错）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程占位/临时目录）。"""
    p.add_argument("--threads", type=int, help="线程数占位（ClustalW 单线程，不注入 argv）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("-outfile", "--outfile", help="输出文件")
    p.add_argument("-output", "--output-format", choices=_OUTPUT_FORMATS,
                   help="输出格式（默认 CLUSTAL）")
    p.add_argument("-type", "--type", "--seqtype", dest="seqtype",
                   choices=("PROTEIN", "DNA"), help="序列类型（省略则自动识别）")
    p.add_argument("-quiet", "--quiet", action="store_true", help="减少控制台输出")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="clustalw-skill",
        description="clustalw native 技能驱动（多序列比对 / 系统发育树，单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("-infile", "--infile", help="输入序列文件（位置参数亦可）")
    pa.add_argument("input", nargs="?", help="输入序列文件（别名 --infile）")
    pa.add_argument("-quicktree", "--quicktree", action="store_true", help="快速近似引导树")
    pa.add_argument("-matrix", "--matrix", help="蛋白权重矩阵（BLOSUM/PAM/GONNET/ID/文件）")
    pa.add_argument("-gapopen", "--gapopen", type=float, help="开 gap 罚分")
    pa.add_argument("-gapext", "--gapext", type=float, help="gap 延伸罚分")
    pa.add_argument("-outorder", "--outorder", choices=("INPUT", "ALIGNED"), help="输出序列顺序")
    pa.add_argument("-stats", "--stats", help="比对统计输出文件")
    pa.add_argument("-newtree", "--newtree", help="写出新引导树文件")
    pa.add_argument("--extra-args", help="透传给 clustalw 的额外参数")
    _add_common_opts(pa)
    _add_runtime_opts(pa)

    # tree
    pt = sub.add_parser("tree", help=SUBCOMMANDS["tree"])
    pt.add_argument("-infile", "--infile", help="输入比对文件（位置参数亦可）")
    pt.add_argument("input", nargs="?", help="输入比对文件（别名 --infile）")
    pt.add_argument("-newtree", "--newtree", help="写出新引导树文件")
    pt.add_argument("-outputtree", "--outputtree", choices=_OUTPUT_TREES, help="树的输出格式")
    pt.add_argument("-clustering", "--clustering", choices=_CLUSTERING, help="聚类方法（默认 NJ）")
    pt.add_argument("-bootstrap", "--bootstrap", type=int, help="bootstrap 重复次数（默认 1000）")
    pt.add_argument("--extra-args", help="透传给 clustalw 的额外参数")
    _add_common_opts(pt)
    _add_runtime_opts(pt)

    # profile
    pp = sub.add_parser("profile", help=SUBCOMMANDS["profile"])
    pp.add_argument("-profile1", "--profile1", help="第一组比对（-profile1=）")
    pp.add_argument("-profile2", "--profile2", help="第二组比对（-profile2=）")
    pp.add_argument("-usetree1", "--usetree1", help="profile1 使用的旧引导树")
    pp.add_argument("-usetree2", "--usetree2", help="profile2 使用的旧引导树")
    pp.add_argument("--extra-args", help="透传给 clustalw 的额外参数")
    _add_common_opts(pp)
    _add_runtime_opts(pp)

    # help
    ph = sub.add_parser("help", help=SUBCOMMANDS["help"])
    _add_runtime_opts(ph)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = ClustalwSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ClustalwSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads
    # 位置参数作为 infile 别名
    if "input" in kw and "infile" not in kw:
        kw["infile"] = kw["input"]

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
