#!/usr/bin/env python3
"""ltr_retriever native 标准入口驱动。

LTR_retriever（上游 oushujun/LTR_retriever，官网见 README）是 LTR 反转录转座子（LTR-RT）
的敏感识别与注释工具：读取基因组 FASTA 与 LTRharvest（genometools）产出的候选文件，经结构
筛选、去冗余（CD-HIT）、蛋白/DNA TE 污染剔除与 TEsorter 分类，输出非冗余 LTR-RT 库
（LTRlib.fa）、全基因组注释（GFF3）与 LTR Assembly Index（LAI）。

本驱动包装官方主脚本 LTR_retriever（子命令 run）；上游依赖（BLAST+/CD-HIT/HMMER/RepeatMasker/
TEsorter 等）由 bioconda ltr_retriever 包一并装入，本驱动不单独管理这些依赖。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -genome genome.fasta -inharvest ltrharvest.out --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程/临时目录：官方 LTR_retriever 支持 -threads（默认 4），--threads 自动注入（本驱动默认 8）；
--tmpdir 注入 TMPDIR 环境变量（meta.optimization.env_vars）。

工作目录约定：官方**无 -output_dir 选项**，产物以「基因组文件名」为前缀（如 genome.fasta.LTRlib.fa、
genome.fasta.out.gff3）写入**当前工作目录**，中间文件归入 LTRretriever-pre<日期>/。请先 cd 到目标
项目目录再调用（容器运行同理，见 README「环境安装」）。
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
    "run": "LTR_retriever：读取 -genome 基因组 FASTA 与 -inharvest 候选，产出非冗余 LTR-RT 库（LTRlib.fa）/ GFF3 / LAI",
}


class LTRRetrieverSkill(base.SkillBase):
    software = "ltr_retriever"
    binary = "LTR_retriever"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/ltr_retriever/meta.yaml（不在 native/ 下），
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

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 LTR_retriever 命令行。"""
        binary = shutil.which(self.binary or self.software)
        if not binary:
            raise RuntimeError(
                f"未找到可执行文件 '{self.binary}'，请先通过 Conda/Docker/Apptainer 安装 "
                "(bioconda ltr_retriever / 官方容器会提供 LTR_retriever 及其依赖)。"
            )

        if subcommand == "run":
            genome = kw.get("genome")
            if not genome:
                raise RuntimeError("run 需要 -genome/--genome（基因组 FASTA，必需）")
            inharvest = kw.get("inharvest")
            if not inharvest:
                raise RuntimeError("run 需要 -inharvest/--inharvest（LTRharvest 候选文件，必需）")
            # LTR_retriever -genome <fasta> -inharvest <candidates> [-threads INT] [options]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd: list[str] = [binary, "-genome", str(genome), "-inharvest", str(inharvest),
                              "-threads", str(threads)]
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
        prog="ltr_retriever-skill",
        description="ltr_retriever native 技能驱动（自动线程/TMPDIR；LTR-RT 识别与注释）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run: LTR_retriever -genome <fasta> -inharvest <candidates> [-threads INT]
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-genome", "--genome", required=True, help="基因组序列 FASTA（LTR_retriever -genome）")
    pr.add_argument("-inharvest", "--inharvest", required=True,
                    help="LTRharvest 候选文件（由 gt ltrharvest 产出，见 modules/genometools）")
    pr.add_argument("--extra-args", dest="extra_args",
                    help="透传给 LTR_retriever 的额外参数（如 -noanno/-minlen/-step，高级用法慎用）")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 LTR_retriever -threads，默认 8）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（同时设 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = LTRRetrieverSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LTRRetrieverSkill()
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
        # LTR_retriever 进度日志走 stderr，stdout 若有内容直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
