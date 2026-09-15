#!/usr/bin/env python3
"""LASTZ native 标准入口驱动（LASTZ 1.04.22）。

LASTZ（BLASTZ 后继，Harris 2007）是双序列/全基因组比对工具，以 BLAST-like 种子扩展
识别基因组间同源区（含大尺度重排、倒位、插入缺失），灵敏高于 MUMmer。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align ref.fasta query.fasta --output=result.maf --format=maf --threads 4
   python main.py align ref.fasta query.fasta --output=result.lav --format=lav \
       --hspthresh=2200 --gappedthresh=4000 --identity=90 --coverage=50
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令形态（lastz 用法，参数名取自官方 1.04.22 手册 README.lastz.html）：
  lastz <target> <query> [--output=<file>] [--format=<type>] [--hspthresh=<score>]
        [--gappedthresh=<score>] [--filter=identity:<min>] [--filter=coverage:<min>]
        [--step=<n>] [--seed=<pattern>] [--chain] [--nogapped] [--notransition]

注意：LASTZ 为单线程程序（无 --threads/-p 选项）——--threads 仅占位接受，不注入命令行；
      官方一致率/覆盖度过滤写作 --filter=identity:<min> / --filter=coverage:<min>
      （文档 14.md 的 --identity=/--coverage= 简写对应本驱动的 --identity/--coverage 参数）。
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
    "align": "LASTZ 比对：lastz <target> <query> → --output=<file>（--format lav/maf/general…）",
}

# 子命令 -> 官方可执行名
_BINARIES = {"align": "lastz"}


class LastzSkill(base.SkillBase):
    software = "lastz"
    binary = "lastz"

    def __init__(self, meta_path: str | Path | None = None):
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _binary_for(self, subcommand: str) -> str:
        try:
            return _BINARIES[subcommand]
        except KeyError:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令惰性解析官方可执行文件（测试通过 monkeypatch 本方法避开安装依赖）。"""
        bin_name = self._binary_for(subcommand)
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'：请先安装 LASTZ（mamba create -n lastz "
                f"-c conda-forge -c bioconda lastz=1.04.22，或 brew install lastz，或源码编译；"
                f"见 README「环境安装」）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。

        LASTZ 单线程，该值仅用于上层调度语义（不注入命令行）。
        """
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构造 lastz 命令行（返回 argv，由 run()/main() 执行）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        binary = self._resolve_sub_binary(subcommand)
        target = kw.get("target")
        query = kw.get("query")
        if not target:
            raise ValueError("align 需要 target（目标/参考序列 FASTA）")
        if not query:
            raise ValueError("align 需要 query（查询序列 FASTA/2bit）")

        cmd: list[str] = [binary, str(target), str(query)]

        if kw.get("output"):
            cmd.append(f"--output={kw['output']}")
        if kw.get("format"):
            cmd.append(f"--format={kw['format']}")
        if kw.get("hspthresh") is not None:
            cmd.append(f"--hspthresh={int(kw['hspthresh'])}")
        if kw.get("gappedthresh") is not None:
            cmd.append(f"--gappedthresh={int(kw['gappedthresh'])}")
        if kw.get("identity") is not None:
            cmd.append(f"--filter=identity:{int(kw['identity'])}")
        if kw.get("coverage") is not None:
            cmd.append(f"--filter=coverage:{int(kw['coverage'])}")
        if kw.get("step") is not None:
            cmd.append(f"--step={int(kw['step'])}")
        if kw.get("seed"):
            cmd.append(f"--seed={kw['seed']}")
        if kw.get("chain"):
            cmd.append("--chain")
        if kw.get("nogapped"):
            cmd.append("--nogapped")
        if kw.get("notransition"):
            cmd.append("--notransition")

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
        prog="lastz-skill",
        description="LASTZ 1.04.22 native 技能驱动（双序列/全基因组比对；单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("target", help="目标/参考序列 FASTA")
    pa.add_argument("query", help="查询序列 FASTA/2bit")
    pa.add_argument("--output", help="输出文件（默认写 stdout）")
    pa.add_argument("--format", default="maf",
                    help="输出格式（lav/maf/axt/sam/general[:fields]/rdotplot/text/cigar…；默认 maf）")
    pa.add_argument("--hspthresh", type=int, help="HSP 得分阈值（低于丢弃）")
    pa.add_argument("--gappedthresh", type=int, help="带间隙扩展得分阈值")
    pa.add_argument("--identity", type=int,
                    help="最小一致率百分比（映射为 --filter=identity:<min>）")
    pa.add_argument("--coverage", type=int,
                    help="最小覆盖度百分比（映射为 --filter=coverage:<min>）")
    pa.add_argument("--step", type=int, help="种子步长（越大越快越不敏感）")
    pa.add_argument("--seed", help="种子模式（如 match12）")
    pa.add_argument("--chain", action="store_true", help="显式启用 chaining（默认已开）")
    pa.add_argument("--nogapped", action="store_true", help="跳过带间隙扩展（仅 HSP，快）")
    pa.add_argument("--notransition", action="store_true", help="降低种子灵敏度（不允许转换）")
    pa.add_argument("--extra-args", help="透传给 lastz 的额外参数")
    _add_runtime_opts(pa)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=str, default="auto",
                   help="占位（LASTZ 单线程，不注入命令行；auto 或正整数均接受）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = LastzSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LastzSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = None if ns.threads in (None, "auto") else ns.threads

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
