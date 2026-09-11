#!/usr/bin/env python3
"""repeatmodeler native 标准入口驱动。

RepeatModeler（www.repeatmasker.org/RepeatModeler/，上游 Dfam-consortium）是从头（de novo）
重复序列家族识别与建模工具，用于构建物种特异性重复库。依赖（RECON / RepeatScout / RMBlast /
TRF / RepeatMasker / cd-hit / LTR_retriever 等）由 bioconda repeatmodeler 包一并装入，
本驱动不单独管理这些依赖。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py build_db ../genome.fasta -name species --engine ncbi --threads 4
   python main.py model -database species --engine ncbi --threads 8            # 默认 8 线程
   python main.py model -database species --threads 8 --LTRStruct              # 追加 LTR 结构发现
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

子命令语义：
- build_db = 包装 BuildDatabase：基因组 FASTA -> <name>-index/（BLAST 库）+ <name>.translation。
  BuildDatabase 原生无并行参数，--threads 仅作为运行期选项被接受、不注入命令行。
- model     = 包装 RepeatModeler：-database <name> -> RM_*/ 目录（consensi.fa(.classified) /
  RM_*.families，供 RepeatMasker -lib 使用）。--threads 自动注入为 -pa（默认 8）。
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
    "build_db": "BuildDatabase：基因组 FASTA -> BLAST 库（<name>-index/ + <name>.translation），供 RepeatModeler 使用",
    "model": "RepeatModeler：-database 跑 RECON/RepeatScout/LTR_retriever 从头建库，产出 RM_*.families / consensi.fa(.classified)",
}


class RepeatModelerSkill(base.SkillBase):
    software = "repeatmodeler"
    binary = "RepeatModeler"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/repeatmodeler/meta.yaml（不在 native/ 下），
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

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（如 BuildDatabase），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda repeatmodeler / 官方容器会同时提供 RepeatModeler / BuildDatabase 等）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 RepeatModeler / BuildDatabase 命令行。"""
        if subcommand == "build_db":
            binary = self._resolve_tool("BuildDatabase")
            genome_fasta = kw.get("genome_fasta")
            if not genome_fasta:
                raise RuntimeError("build_db 需要 genome_fasta（基因组 FASTA，位置参数）")
            name = kw.get("name")
            if not name:
                raise RuntimeError("build_db 需要 -name/--name（输出数据库名，必需）")
            # BuildDatabase [-engine <engine>] -name <name> <fasta>；原生无并行参数，
            # 线程仅作为运行期选项被接受，不注入命令行（见 meta.optimization 注释）
            cmd: list[str] = [binary, "-name", str(name)]
            engine = kw.get("engine") or "ncbi"
            if engine:
                cmd += ["-engine", str(engine)]
            cmd += [str(genome_fasta)]
        elif subcommand == "model":
            binary = self._resolve_binary()
            database = kw.get("database")
            if not database:
                raise RuntimeError("model 需要 -database/--database（BuildDatabase 输出的库名，必需）")
            # RepeatModeler -database <name> [-engine <engine>] [-pa N] [-LTRStruct]
            cmd = [binary, "-database", str(database)]
            engine = kw.get("engine") or "ncbi"
            if engine:
                cmd += ["-engine", str(engine)]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["-pa", str(threads)]
            if kw.get("ltr_struct"):
                cmd += ["-LTRStruct"]
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="repeatmodeler-skill",
        description="repeatmodeler native 技能驱动（自动线程/TMPDIR；从头重复序列家族建模）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # build_db: BuildDatabase -name <name> [-engine <engine>] <genome_fasta>
    pb = sub.add_parser("build_db", help=SUBCOMMANDS["build_db"])
    pb.add_argument("genome_fasta", help="基因组 FASTA（位置参数）")
    pb.add_argument("-name", "--name", required=True, help="输出数据库名（必需；RepeatModeler -database 指向该名）")
    pb.add_argument("-engine", "--engine", default="ncbi", help="搜索引擎（默认 ncbi；RMBlast 兼容引擎）")
    pb.add_argument("--extra-args", dest="extra_args", help="透传给 BuildDatabase 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    # model: RepeatModeler -database <name> [-engine <engine>] [-pa N] [--LTRStruct]
    pm = sub.add_parser("model", help=SUBCOMMANDS["model"])
    pm.add_argument("-database", "--database", required=True, help="数据库名（必需；BuildDatabase -name 的产物）")
    pm.add_argument("-engine", "--engine", default="ncbi", help="搜索引擎（默认 ncbi；RMBlast 兼容引擎）")
    pm.add_argument("--LTRStruct", action="store_true",
                    help="运行 LTR 结构发现（LTR_retriever；更慢，真核大基因组按需）")
    pm.add_argument("--extra-args", dest="extra_args", help="透传给 RepeatModeler 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pm)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（model 注入 -pa；build_db 原生无并行参数）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = RepeatModelerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RepeatModelerSkill()
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
        # build_db / model 的进度日志走 stderr，stdout 若有内容直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
