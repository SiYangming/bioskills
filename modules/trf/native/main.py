#!/usr/bin/env python3
"""trf（Tandem Repeats Finder）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py scan genome.fasta                         # 上游默认 2 7 7 80 10 50 500
   python main.py scan genome.fasta -m -d                   # 追加屏蔽序列(.mask) + 数据文件(.dat)
   python main.py scan genome.fasta -m -d -h                # 教学命令（-h 关闭默认 HTML）
   python main.py scan genome.fasta --min-score 50 --max-period 500 -m -d --threads 1
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

trf 的位置参数与选项（上游 usage）：
    trf <File> <Match> <Mismatch> <Delta> <PM> <PI> <Minscore> <MaxPeriod> [options]
    -m  masked sequence file（N 屏蔽序列）
    -f  flanking sequence（记录侧翼序列）
    -d  data file（*.dat）
    -h  suppress html output（关闭默认 HTML 输出，并自动开启 -d）
    -r  no redundancy elimination   -l <n>  -ngs  -u  -v

说明：
- trf 为单线程程序：每个子命令接受 --threads 作为运行期协议位，但**不注入命令行**。
- 产物写到输入 FASTA 同目录，文件名以「输入名 + 7 个参数值」为前缀（见 README）。
- ⚠️ 上游 TRF 常规模式**成功时退出码为 1**（上游文档：仅 `-ngs` 模式 "returns 0 on success"），
  故本驱动覆写 run()：0/1 均视为成功并归一化为 0，其余（如找不到输入文件的 255）判为失败。
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
    "scan": "trf：在 FASTA 中查找并展示串联重复（7 个数值参数 + -m/-d/-h 等选项）",
}

# trf 的 7 个数值位置参数默认值（上游 Quick Start 推荐：2 7 7 80 10 50 500）
DEFAULT_PARAMS = (2, 7, 7, 80, 10, 50, 500)


class TrfSkill(base.SkillBase):
    software = "trf"
    binary = "trf"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/trf/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / optimization 等真正读到配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 trf 命令行。"""
        if subcommand != "scan":
            raise RuntimeError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        genome_fasta = kw.get("genome_fasta")
        if not genome_fasta:
            raise RuntimeError("scan 需要 genome_fasta（待分析序列 FASTA）")
        # trf 以「进程 CWD + 输入文件 basename」为前缀写出产物，故统一用绝对路径，
        # run() 再把 CWD 设为输入文件所在目录，使产物落在输入 FASTA 同目录。
        genome_fasta = str(Path(genome_fasta).resolve())

        def _num(name: str, default: int) -> object:
            value = kw.get(name)
            return default if value is None else value

        params = [
            _num("match_weight", DEFAULT_PARAMS[0]),
            _num("mismatch_weight", DEFAULT_PARAMS[1]),
            _num("indel_weight", DEFAULT_PARAMS[2]),
            _num("match_prob", DEFAULT_PARAMS[3]),
            _num("indel_prob", DEFAULT_PARAMS[4]),
            _num("min_score", DEFAULT_PARAMS[5]),
            _num("max_period", DEFAULT_PARAMS[6]),
        ]
        # trf <File> <Match> <Mismatch> <Delta> <PM> <PI> <Minscore> <MaxPeriod> [options]
        cmd: list[str] = [binary, str(genome_fasta)] + [str(p) for p in params]

        # -m 屏蔽后序列 / -d 数据文件 / -h 关闭默认 HTML（上游语义，并自动开启 -d）
        if kw.get("mask"):
            cmd.append("-m")
        if kw.get("data"):
            cmd.append("-d")
        if kw.get("html"):
            cmd.append("-h")

        # 高级透传（慎用，如 -f / -r / -l <n> / -ngs）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 注意：trf 单线程，--threads 仅作运行期协议位，不注入命令行；TMPDIR 由 env_vars 注入。
        return cmd

    # trf 常规模式成功返回 1（-ngs 返回 0）；0/1 视为成功，其余为错误（如输入文件不存在返回 255）。
    _SUCCESS_CODES = frozenset({0, 1})

    def run(self, subcommand: str, **kw) -> base.RunResult:
        """执行 trf，并按上游退出码语义判定成功（0/1 成功，归一化为 0）。

        trf 把产物写到**当前工作目录**（前缀取输入文件 basename），故此处把 CWD
        设为输入 FASTA 所在目录，保证产物落在输入文件同目录（与 README 一致）。
        """
        args = self.build_command(subcommand, **kw)
        fasta = kw.get("genome_fasta")
        cwd = str(Path(fasta).resolve().parent) if fasta else None
        result = base.run_command(args, env=self.env_vars, check=False, cwd=cwd)
        if result.returncode not in self._SUCCESS_CODES:
            raise RuntimeError(
                f"trf 执行失败 (code={result.returncode}): {' '.join(args)}\n"
                f"stderr:\n{result.stderr}"
            )
        result.returncode = 0
        return result


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="trf-skill",
        description="trf（Tandem Repeats Finder）native 技能驱动（串联重复序列查找）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # scan: trf <File> <Match> <Mismatch> <Delta> <PM> <PI> <Minscore> <MaxPeriod> [options]
    # add_help=False：把 -h 让给 trf 的「关闭 HTML」语义，另用 --help 提供帮助。
    ps = sub.add_parser("scan", help=SUBCOMMANDS["scan"], add_help=False)
    ps.add_argument("genome_fasta", help="待分析序列 FASTA（trf 的 <File> 位置参数）")
    ps.add_argument("--match-weight", dest="match_weight", type=int,
                    help="匹配权重 Match（默认 2）")
    ps.add_argument("--mismatch-weight", dest="mismatch_weight", type=int,
                    help="不匹配罚分 Mismatch（默认 7）")
    ps.add_argument("--indel-weight", dest="indel_weight", type=int,
                    help="INDEL 罚分 Delta（默认 7）")
    ps.add_argument("--match-prob", dest="match_prob", type=int,
                    help="匹配概率 PM（默认 80）")
    ps.add_argument("--indel-prob", dest="indel_prob", type=int,
                    help="INDEL 概率 PI（默认 10）")
    ps.add_argument("--min-score", dest="min_score", type=int,
                    help="最小比对得分 Minscore（默认 50）")
    ps.add_argument("--max-period", dest="max_period", type=int,
                    help="最大重复周期 MaxPeriod（默认 500；程序可查 1–2000）")
    ps.add_argument("-m", "--mask", action="store_true",
                    help="生成 N 屏蔽后的序列文件（trf -m，*.mask）")
    ps.add_argument("-d", "--data", action="store_true",
                    help="生成逐条重复的数据文件（trf -d，*.dat）")
    ps.add_argument("-h", "--html", "--suppress-html", dest="html", action="store_true",
                    help="对应 trf 的 -h：关闭默认 HTML 输出（TRF 默认即产出 HTML；-h 同时自动开启 -d）")
    ps.add_argument("--extra-args", dest="extra_args",
                    help="透传给 trf 的额外选项（如 -f / -r / -l <n> / -ngs），慎用")
    _add_runtime_opts(ps)
    ps.add_argument("--help", action="help", help="显示 scan 子命令帮助")

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程协议位 / 临时目录）。"""
    p.add_argument("--threads", type=int, help="线程数协议位（trf 单线程，接受但不注入命令行）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = TrfSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = TrfSkill()
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

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
