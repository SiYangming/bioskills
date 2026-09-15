#!/usr/bin/env python3
"""finishersc native 标准入口驱动（FinisherSC / Finishing Tool v2.1，Python 2 脚本）。

FinisherSC 以 PacBio 长读对 de novo 组装做 repeat-aware 迭代升级（补 gap + 纠错），官方调用形态：
    python finisherSC.py -par 8 -l True -o contigs.fasta_improved3.fasta ./ /path/to/mummer/bin/
脚本 argv（argparse）为：folderName mummerLink [-p pickup] [-o mapcontigs] [-f True] [-par N] [-l True]；
关键输出为 <folderName>/improved3.fasta。依赖 MUMmer（nucmer/show-coords 等）与 Python 2。

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py finish ./ /opt/mummer-4.0.0beta2/bin/ --threads 8 --large
   python main.py finish ./mummer/bin/ --no-... 等见 --help
2. Agent Function Calling / Schema 自省：
   python main.py --schema | --list-commands

线程优先级：用户显式 --threads > optimization.per_subcommand_threads.finish > default_cpus（注入 -par）。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "finish": "FinisherSC 主流程（contigs.fasta + raw_reads.fasta -> improved3.fasta；"
              "形如 -par N -l True -f True -p <pickup> -o <mapcontigs> <folder> <mummer>）",
}

# finisherSC.py 候选位置（{conda} 渲染为 CONDA_PREFIX）
_SCRIPT_GLOBS = [
    "{conda}/bin/finisherSC.py",
    "{conda}/share/finishingTool*/finisherSC.py",
    "~/software/kakitone-finishingTool*/finisherSC.py",
    "~/software/finishingTool*/finisherSC.py",
    "/opt/finisherSC/finisherSC.py",
    "/opt/finishingTool/finisherSC.py",
]


class FinisherSCSkill(base.SkillBase):
    software = "finishersc"
    binary = "finisherSC.py"

    def _python(self) -> str:
        """FinisherSC 为 Python 2 脚本；运行时解释器可用 FINISHERSC_PYTHON 覆盖。"""
        return os.environ.get("FINISHERSC_PYTHON") or "python"

    def _resolve_binary(self) -> str:
        """定位 finisherSC.py 脚本（惰性；测试用 monkeypatch 覆盖，不依赖工具已安装）。"""
        env_home = os.environ.get("FINISHERSC_HOME")
        if env_home:
            cand = Path(env_home) / "finisherSC.py"
            if cand.is_file():
                return str(cand)
        path = base.which("finisherSC.py")
        if path:
            return path
        conda = os.environ.get("CONDA_PREFIX", "")
        for pat in _SCRIPT_GLOBS:
            p = pat.format(conda=conda)
            if p.startswith("~"):
                p = str(Path(p).expanduser())
            hits = sorted(glob.glob(p))
            if hits:
                return hits[0]
        raise RuntimeError(
            "未找到 finisherSC.py；请安装（native/install.sh 源码部署，或自建容器），"
            "或设置 FINISHERSC_HOME 指向含 finisherSC.py 的目录"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        folder = kw.get("folder") or kw.get("input")
        mummer = kw.get("mummer")
        if not folder:
            raise ValueError("finish 缺少必填参数 folder（destinedFolder，须含 contigs.fasta 与 raw_reads.fasta）")
        if not mummer:
            raise ValueError("finish 缺少必填参数 mummer（MUMmer 可执行文件目录）")

        cmd: list[str] = [self._python(), self._resolve_binary()]

        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-par", str(threads)]

        # 官方 -l/-f 需显式传字符串 "True"，故以布尔开关映射
        if kw.get("large"):
            cmd += ["-l", "True"]
        if kw.get("fast"):
            cmd += ["-f", "True"]
        pickup = kw.get("pickup")
        if pickup:
            cmd += ["-p", str(pickup)]
        mapcontigs = kw.get("mapcontigs")
        if mapcontigs:
            cmd += ["-o", str(mapcontigs)]

        # 位置参数：folderName mummerLink
        cmd += [str(folder), str(mummer)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖并行线程数（注入 -par）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="finishersc-skill",
        description="finishersc native 技能驱动（FinisherSC v2.1，Python 2 脚本；自动注入 -par 线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pf = sub.add_parser("finish", help=SUBCOMMANDS["finish"])
    pf.add_argument("folder", help="destinedFolder（须含 contigs.fasta 与 raw_reads.fasta）")
    pf.add_argument("mummer", help="MUMmer 可执行文件目录（含 nucmer / show-coords 等）")
    pf.add_argument("-l", "--large", action="store_true",
                    help="大 contig 集模式（对应 -l True）")
    pf.add_argument("-f", "--fast", action="store_true",
                    help="快速模式（对应 -f True；速度更快、质量略有折中）")
    pf.add_argument("-p", "--pickup",
                    help="断点续跑起点（noEmbed.fasta|improved.fasta|improved2.fasta）")
    pf.add_argument("-o", "--mapcontigs",
                    help="将新 contig 映射回旧 contig（形如 contigs.fasta_improved3.fasta）")
    pf.add_argument("--extra-args", dest="extra_args", help="透传给 finisherSC.py 的额外参数")
    _add_runtime_opts(pf)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = FinisherSCSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FinisherSCSkill()
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
