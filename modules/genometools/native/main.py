#!/usr/bin/env python3
"""genometools(gt) native 标准入口驱动（LTRharvest LTR 反转录转座子预测链路）。

GenomeTools 把大量基因组分析子命令集中到单一二进制 `gt`。本驱动封装重复序列分析
流程最常用的两个子命令（RepeatModeler -LTRStruct / LTR_retriever 依赖）：
- suffixerator = gt suffixerator：为基因组 FASTA 建增强后缀数组（ESA）索引；
- ltrharvest  = gt ltrharvest ：基于该索引预测 LTR 反转录转座子（FASTA + GFF3）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py suffixerator -db genome.fasta -indexname genome --threads 4
   python main.py ltrharvest -index genome -out ltrharvest.out \
       -outinner ltrharvest.inner -gff3 ltrharvest.gff3
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程/临时目录：gt suffixerator 与 ltrharvest 均无原生线程参数，--threads 仅作为运行期
选项被接受、不注入命令行（与 repeatmodeler 的 build_db 同策略）；--tmpdir 注入 TMPDIR
环境变量（meta.optimization.env_vars）。

索引开关（依官方 1.6.x 选项核实，见 src/core/encseq_options.c 与 src/match/index_options.c）：
-tis/-suf/-lcp 属索引表、-des/-ssp/-sds 属编码描述表、-dna 声明 DNA 输入；
默认按教学链路（gt suffixerator -db ... -tis -suf -lcp -des -ssp -sds -dna）全部注入，
可用 --no-<开关> 单独关闭（-sds 依赖 -des：关闭 -des 时须同时关闭 -sds）。
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
    "suffixerator": "gt suffixerator：基因组 FASTA -> 增强后缀数组（ESA）索引 <indexname>.{esq,ssp,des,sds,suf,lcp,md5}",
    "ltrharvest": "gt ltrharvest：基于 ESA 索引预测 LTR 反转录转座子（-out/-outinner FASTA + -gff3）",
}

# suffixerator 的索引/编码开关（官方 1.6.x 选项；默认全部注入，可用 --no-<开关> 关闭）
INDEX_SWITCHES = ("tis", "suf", "lcp", "des", "ssp", "sds", "dna")


class GenomeToolsSkill(base.SkillBase):
    software = "genometools"
    binary = "gt"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/genometools/meta.yaml（不在 native/ 下），
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
        """根据子命令与参数构建 gt 命令行。"""
        binary = shutil.which(self.binary or self.software)
        if not binary:
            raise RuntimeError(
                f"未找到可执行文件 '{self.binary}'，请先通过 Conda/Docker/Apptainer 安装 "
                "(bioconda genometools-genometools / 官方容器会提供 gt)。"
            )

        if subcommand == "suffixerator":
            db = kw.get("db")
            if not db:
                raise RuntimeError("suffixerator 需要 -db/--db（输入基因组 FASTA）")
            indexname = kw.get("indexname")
            if not indexname:
                raise RuntimeError("suffixerator 需要 -indexname（输出索引前缀）")
            cmd: list[str] = [binary, "suffixerator", "-db", str(db), "-indexname", str(indexname)]
            # -sds 依赖 -des（gt_option_imply），关闭 -des 时必须同时关闭 -sds
            if kw.get("sds", True) and not kw.get("des", True):
                raise RuntimeError("-sds 依赖 -des：请勿只关闭 -des，需同时传 --no-sds")
            for sw in INDEX_SWITCHES:
                if kw.get(sw, True):
                    cmd.append(f"-{sw}")
        elif subcommand == "ltrharvest":
            index = kw.get("index")
            if not index:
                raise RuntimeError("ltrharvest 需要 -index/--index（suffixerator 输出的索引前缀）")
            cmd = [binary, "ltrharvest", "-index", str(index)]
            for opt in ("out", "outinner", "gff3"):
                val = kw.get(opt)
                if val:
                    cmd += [f"-{opt}", str(val)]
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
        prog="genometools-skill",
        description="genometools(gt) native 技能驱动（ESA 索引 + LTRharvest LTR 反转录转座子预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # suffixerator: gt suffixerator -db <fasta> -indexname <prefix> [-tis -suf -lcp -des -ssp -sds -dna]
    ps = sub.add_parser("suffixerator", help=SUBCOMMANDS["suffixerator"])
    ps.add_argument("-db", "--db", required=True, help="输入基因组 FASTA（gt -db）")
    ps.add_argument("-indexname", "--indexname", required=True, help="输出索引前缀（产物 <indexname>.*）")
    for sw in INDEX_SWITCHES:
        ps.add_argument(f"--no-{sw}", dest=sw, action="store_false", default=True,
                        help=f"关闭索引/编码开关 -{sw}（默认注入，见文件头注）")
    ps.add_argument("--extra-args", dest="extra_args", help="透传给 gt suffixerator 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ps)

    # ltrharvest: gt ltrharvest -index <prefix> [-out F] [-outinner F] [-gff3 F]
    pl = sub.add_parser("ltrharvest", help=SUBCOMMANDS["ltrharvest"])
    pl.add_argument("-index", "--index", required=True, help="ESA 索引前缀（suffixerator -indexname 的产物）")
    pl.add_argument("-out", "--out", help="LTR 反转录转座子 FASTA 输出")
    pl.add_argument("-outinner", "--outinner", help="内部区域（inner region）FASTA 输出")
    pl.add_argument("-gff3", "--gff3", help="预测结果 GFF3 输出")
    pl.add_argument("--extra-args", dest="extra_args", help="透传给 gt ltrharvest 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pl)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（gt 该子命令无线程参数，仅接受不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（同时设 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GenomeToolsSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GenomeToolsSkill()
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
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
