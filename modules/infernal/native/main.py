#!/usr/bin/env python3
"""infernal native 标准入口驱动（Rfam/ncRNA 同源搜索，cmsearch + cmpress）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py cmpress Rfam.cm                                # 索引 .cm → .cm.i1f/.i1m/.i1p/.i1i
   python main.py cmpress Rfam.cm --extra-args "-f"               # -f 强制重建索引
   python main.py cmsearch Rfam.cm genome.fasta --cut_ga --nohmmonly --rfam --noali \
       --threads 8 --tblout rfam_out.tab -o rfam_out.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入临时目录（--tmpdir，同时设 TMPDIR）；cmsearch 自动注入线程
（--threads → cmsearch 的 --cpu，默认见 meta optimization.per_subcommand_threads）。

教学典型流程（对应 README「实战示例」，等价能力由本驱动的 cmpress/cmsearch 提供）：
  cmpress Rfam.cm
  cmsearch --cut_ga --nohmmonly --rfam --noali --cpu 8 --tblout rfam_out.tab \
           Rfam.cm genome.fasta > rfam_out.txt
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
    "cmpress": "cmpress：压缩/索引 CM 数据库（.cm → .cm.i1f/.cm.i1m/.cm.i1p/.cm.i1i 索引族，供 cmsearch 使用）",
    "cmsearch": "cmsearch：用 CM 集合搜索基因组/序列库（主输出 + --tblout 表格；教学 --cut_ga --rfam --noali）",
}


class InfernalSkill(base.SkillBase):
    software = "infernal"
    # execution.binary 登记 cmsearch 为代表性可执行入口（infernal 无同名总入口）
    binary = "cmsearch"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/infernal/meta.yaml（不在 native/ 下），
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
        """解析配套可执行文件（如 cmpress），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda infernal / 官方容器会同时提供 cmsearch / cmpress / cmscan / cmbuild 等）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 infernal 命令行。"""
        if subcommand == "cmpress":
            # cmpress [-f] <cmfile>：单线程快跑，不注入 --cpu（线程值仅作调度提示）
            binary = self._resolve_tool("cmpress")
            cm_database = kw.get("cm_database")
            if not cm_database:
                raise RuntimeError("cmpress 需要 cm_database（CM 数据库 .cm 文件，位置参数）")
            cmd: list[str] = [binary, str(cm_database)]
        elif subcommand == "cmsearch":
            # cmsearch [options] <cmfile> <seqdb>：CPU 密集，自动注入 --cpu
            binary = self._resolve_binary()
            threads = self._effective_threads("cmsearch", kw.get("threads"))
            cm_database = kw.get("cm_database")
            genome_fasta = kw.get("genome_fasta")
            if not cm_database:
                raise RuntimeError("cmsearch 需要 cm_database（CM 数据库 .cm 文件，位置参数）")
            if not genome_fasta:
                raise RuntimeError("cmsearch 需要 genome_fasta（搜索目标序列库，位置参数）")

            cmd = [binary]
            # 教学典型开关（Rfam 流程）：--cut_ga 用 GA 收集阈值、--nohmmonly 关闭 HMM-only、
            # --rfam 用 Rfam 专属选项、--noali 不显示比对
            for flag, key in (
                ("--cut_ga", "cut_ga"),
                ("--nohmmonly", "nohmmonly"),
                ("--rfam", "rfam"),
                ("--noali", "noali"),
            ):
                if kw.get(key):
                    cmd += [flag]
            cmd += ["--cpu", str(threads)]

            tblout = kw.get("tblout")
            if tblout:
                cmd += ["--tblout", str(tblout)]
            output = kw.get("output")
            if output:
                cmd += ["-o", str(output)]
            evalue = kw.get("evalue")
            if evalue is not None:
                cmd += ["-E", str(evalue)]

            cmd += [str(cm_database), str(genome_fasta)]
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用；如 cmpress 的 -f 强制重建索引）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="infernal-skill",
        description="infernal native 技能驱动（自动线程/临时目录；cmpress 索引 CM 库 + cmsearch 搜索 RNA 同源）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # cmpress: cmpress <cm_database>
    pc = sub.add_parser("cmpress", help=SUBCOMMANDS["cmpress"])
    pc.add_argument("cm_database", help="CM 数据库文件（.cm，如 Rfam.cm；生成同目录 .cm.i1f/.i1m/.i1p/.i1i）")
    pc.add_argument("--extra-args", dest="extra_args", help="透传给 cmpress 的额外参数（如 -f 强制重建索引）")
    _add_runtime_opts(pc)

    # cmsearch: cmsearch [options] <cm_database> <genome_fasta>
    ps = sub.add_parser("cmsearch", help=SUBCOMMANDS["cmsearch"])
    ps.add_argument("cm_database", help="CM 数据库文件（.cm，如 Rfam.cm；需先 cmpress 索引或直接支持平文件）")
    ps.add_argument("genome_fasta", help="搜索目标序列库（基因组/转录组 FASTA/FASTQ，可 .gz）")
    ps.add_argument("--cut-ga", dest="cut_ga", action="store_true",
                    help="用 GA 收集阈值（gathering cutoff）作为报告/包含阈值（Rfam 教学典型）")
    ps.add_argument("--nohmmonly", action="store_true",
                    help="关闭 HMM-only 快速模式，强制完整 CM 流程（Rfam 教学典型，慢但更准）")
    ps.add_argument("--rfam", action="store_true",
                    help="使用 Rfam 专属搜索选项（仅当搜索 Rfam.cm 库时）")
    ps.add_argument("--noali", action="store_true",
                    help="主输出中不显示比对（省空间/加快，Rfam 教学典型）")
    ps.add_argument("--tblout", help="表格输出文件（每命中一行，如 rfam_out.tab；官方推荐易解析）")
    ps.add_argument("-o", "--output", help="主输出文件（如 rfam_out.txt；缺省 stdout）")
    ps.add_argument("-E", "--evalue", type=float, help="报告阈值 E-value（与 --cut-ga 二选一风格）")
    ps.add_argument("--extra-args", dest="extra_args", help="透传给 cmsearch 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 cmsearch 的 --cpu）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = InfernalSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = InfernalSkill()
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

    # 输出文件（cmpress 索引 / cmsearch -o、--tblout）由二进制自行落盘；stdout/stderr 原样透传
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
