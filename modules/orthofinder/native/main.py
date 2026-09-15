#!/usr/bin/env python3
"""orthofinder native 标准入口驱动。

OrthoFinder（v2.5.5）— 同源基因聚类全流程：一条命令完成 orthogroups / orthologues /
基因树 / 有根物种树 / 基因复制事件推断，比 OrthoMCL 快 10-100 倍、无需数据库。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -f input_proteins -S diamond -t 8 -M dendroblast -o results
   python main.py resume -b results/OrthoFinder/Results_input_proteins -t 8
   python main.py help
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对照 OrthoFinder 2.5.5 help）：
  run     orthofinder -f <dir> -t <threads> -a <threads> -S <search> [-M method] [-I infl]
                     [-o dir] [-n name] [-A msa] [-T tree] [-s tree] [-x xml] [-d] [-op|-og|-os|-oa|-ot]
  resume  orthofinder -b <prev_dir> [-f <new_dir>] -t <threads> -a <threads> -S <search> [...]
  help    orthofinder -h
线程优先级 --threads > per_subcommand_threads > default_cpus（同时注入 -t 与 -a）。
注意：OrthoFinder 2.5.5 无专用 --version 旗标，版本号在每次运行的启动横幅打印
（"OrthoFinder version 2.5.5 ..."）；本驱动的 help 子命令即 `orthofinder -h`。
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
    "run": "全流程同源聚类：orthofinder -f <dir> -S diamond -t <threads> [-M dendroblast|msa]",
    "resume": "从既有结果续跑：orthofinder -b <prev_dir> [-f <new_dir>] -t <threads>",
    "help": "打印 OrthoFinder 帮助与版本横幅（orthofinder -h）",
}

# 提前停止子命令：值 -> orthofinder 短选项
_STOP_FLAGS = {
    "op": "-op",
    "og": "-og",
    "os": "-os",
    "oa": "-oa",
    "ot": "-ot",
}


class OrthofinderSkill(base.SkillBase):
    software = "orthofinder"
    binary = "orthofinder"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 orthofinder 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_binary()

        if subcommand == "help":
            return [bin_path, "-h"]

        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "run":
            return self._build_run(bin_path, threads, **kw)
        return self._build_resume(bin_path, threads, **kw)

    def _common_flags(self, kw: dict) -> list[str]:
        """run/resume 共用的可选参数（-S/-M/-I/-A/-T/-s/-x/-d 与停止标志）。"""
        cmd: list[str] = []
        cmd += ["-S", str(kw.get("search") or "diamond")]
        if kw.get("method"):
            cmd += ["-M", str(kw["method"])]
        if kw.get("inflation") is not None:
            cmd += ["-I", str(kw["inflation"])]
        if kw.get("msa_program"):
            cmd += ["-A", str(kw["msa_program"])]
        if kw.get("tree_program"):
            cmd += ["-T", str(kw["tree_program"])]
        if kw.get("species_tree"):
            cmd += ["-s", str(kw["species_tree"])]
        if kw.get("orthoxml"):
            cmd += ["-x", str(kw["orthoxml"])]
        if kw.get("dna"):
            cmd.append("-d")
        only = kw.get("only")
        if only:
            if only not in _STOP_FLAGS:
                raise RuntimeError(
                    f"only 仅支持 {'/'.join(_STOP_FLAGS)}（收到: {only}）"
                )
            cmd.append(_STOP_FLAGS[only])
        return cmd

    def _build_run(self, bin_path: str, nthreads: int, **kw) -> list[str]:
        proteomes = kw.get("proteomes_dir") or kw.get("input")
        if not proteomes:
            raise RuntimeError("run 缺少必填参数 proteomes_dir（-f 输入目录，每物种一个蛋白 FASTA）")
        cmd = [bin_path, "-f", str(proteomes), "-t", str(nthreads), "-a", str(nthreads)]
        cmd += self._common_flags(kw)
        if kw.get("output_dir"):
            cmd += ["-o", str(kw["output_dir"])]
        if kw.get("name"):
            cmd += ["-n", str(kw["name"])]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def _build_resume(self, bin_path: str, nthreads: int, **kw) -> list[str]:
        prev = kw.get("previous_results_dir") or kw.get("blast_dir")
        if not prev:
            raise RuntimeError("resume 缺少必填参数 previous_results_dir（-b 上次结果目录）")
        cmd = [bin_path, "-b", str(prev), "-t", str(nthreads), "-a", str(nthreads)]
        if kw.get("proteomes_dir"):
            cmd += ["-f", str(kw["proteomes_dir"])]
        cmd += self._common_flags(kw)
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
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="orthofinder-skill",
        description="orthofinder native 技能驱动（同源基因聚类，自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    def _add_common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("-S", "--search", default="diamond", help="序列搜索程序（默认 diamond）")
        sp.add_argument("-M", "--method", choices=("dendroblast", "msa"), help="基因树推断方法")
        sp.add_argument("-I", "--inflation", type=float, help="MCL inflation 参数")
        sp.add_argument("-A", "--msa-program", help="MSA 程序（需 -M msa）")
        sp.add_argument("-T", "--tree-program", help="基因树程序（需 -M msa）")
        sp.add_argument("-s", "--species-tree", help="用户指定的有根物种树（Newick）")
        sp.add_argument("-x", "--orthoxml", help="OrthoXML 输出信息文件")
        sp.add_argument("-d", "--dna", action="store_true", help="输入为 DNA 序列")
        sp.add_argument("--only", choices=tuple(_STOP_FLAGS), help="提前停止：op/og/os/oa/ot")
        sp.add_argument("--extra-args", help="透传给 orthofinder 的额外参数")
        _add_runtime_opts(sp)

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("input", nargs="?", help="输入目录（别名 --proteomes-dir）")
    pr.add_argument("-f", "--proteomes-dir", help="输入目录：每物种一个蛋白 FASTA")
    pr.add_argument("-o", "--output-dir", help="非默认输出目录")
    pr.add_argument("-n", "--name", help="结果目录名后缀")
    _add_common(pr)

    # resume
    ps = sub.add_parser("resume", help=SUBCOMMANDS["resume"])
    ps.add_argument("previous_results_dir", help="上次结果目录（-b）")
    ps.add_argument("-f", "--proteomes-dir", help="新增物种的输入目录（可选）")
    _add_common(ps)

    # help
    ph = sub.add_parser("help", help=SUBCOMMANDS["help"])
    _add_runtime_opts(ph)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("-t", "--threads", type=int, help="覆盖默认线程数（同时注入 -t 与 -a）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = OrthofinderSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OrthofinderSkill()
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
