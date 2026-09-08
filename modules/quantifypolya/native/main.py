#!/usr/bin/env python3
"""quantifypolya native 标准入口驱动（QuantifyPolyA R 包，经 Rscript 调用）。

QuantifyPolyA（sourceforge 项目 quantifypoly-a）以 R 包形态分发（无独立命令行
二进制），用于长读 / 3' end RNA-seq poly(A) 位点定量与 APA 动态度量。本驱动用
Rscript 运行同目录 run_quantifypolya.R（参数经临时 params.tsv 传递，规避 R 侧
引号转义），完成 Load.PolyA -> [Remove.IP] -> Cluster.PolyA -> [Annotate.PolyA]
-> [Filter.PolyA] -> Quantify.* 的标准流程并输出表格。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py quant --bed-dir Human_MAQC --outdir results \
       --gff annotation.gff3 --col-data colData.tsv \
       --contrast condition,Brain,UHR --quant-mode canonical --threads 8
   python main.py quant --bed-files a.bed,b.bed --outdir results \
       --fasta genome.fa --max-gapwidth 24
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

产物（outdir 下）：polyA_sites.tsv（位点/簇全表，含注释与每样本计数）、
apa_<mode>.tsv（组间 APA 动态度量）、QuantifyPolyA.rds（可选，供 Visualize.PolyA）。

前置：R >= 4.0（推荐 4.2+）且已安装 QuantifyPolyA 0.3.0 及其全部依赖 ——
一键安装 `Rscript native/install_deps_QuantifyPolyA.R`（详见 README「环境安装」）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

SUBCOMMANDS = {
    "quant": "poly(A) 位点定量 + APA 动态度量（Load→Cluster→Annotate→Quantify.*，输出表格）",
}

QUANT_MODES = ("canonical", "gene", "split", "cncapa")


class QuantifyPolyASkill(base.SkillBase):
    software = "quantifypolya"
    binary = "Rscript"

    def _driver(self) -> Path:
        return _HERE / "run_quantifypolya.R"

    def _abspath(self, v) -> str:
        return os.path.abspath(os.path.expanduser(str(v)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """quant：写 params.tsv 并构造 `Rscript run_quantifypolya.R <params>`。"""
        if subcommand != "quant":
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        rscript = self._resolve_binary()

        bed_dir = kw.get("bed_dir")
        bed_files = kw.get("bed_files")
        outdir = kw.get("outdir")
        if not (bed_dir or bed_files):
            raise RuntimeError("quant 需要输入：--bed-dir <含 .bed 的目录> 或 --bed-files <f1.bed,f2.bed>")
        if not outdir:
            raise RuntimeError("quant 需要 --outdir 输出目录（--help 查看）")

        tmpdir = self.make_tmpdir("quantifypolya_")
        params = Path(tmpdir) / "params.tsv"
        pairs: list[tuple[str, str]] = []
        if bed_dir:
            pairs.append(("bed_dir", self._abspath(bed_dir)))
        else:
            if isinstance(bed_files, str):
                files = [f.strip() for f in bed_files.split(",") if f.strip()]
            else:
                files = [str(f) for f in bed_files]
            if not files:
                raise RuntimeError("--bed-files 不能为空")
            pairs.append(("bed_files", ",".join(self._abspath(f) for f in files)))
        pairs.append(("outdir", self._abspath(outdir)))

        for key in ("fasta", "gff", "col_data"):
            v = kw.get(key)
            if v:
                pairs.append((key, self._abspath(v)))
        if kw.get("contrast"):
            pairs.append(("contrast", str(kw["contrast"])))
        mode = str(kw.get("quant_mode", "canonical"))
        if mode not in QUANT_MODES:
            raise RuntimeError(f"--quant-mode 必须是 {'|'.join(QUANT_MODES)}（收到: {mode}）")
        pairs.append(("quant_mode", mode))
        pairs.append(("max_gapwidth", str(int(kw.get("max_gapwidth") or 24))))
        for key in ("min_count", "min_sample"):
            v = kw.get(key)
            if v is not None:
                pairs.append((key, str(int(v))))
        threads = kw.get("threads")
        if threads is not None and not (isinstance(threads, str) and threads.lower() == "auto"):
            pairs.append(("threads", str(int(threads))))
        if kw.get("save_rds"):
            pairs.append(("save_rds", "TRUE"))
        if kw.get("quiet"):
            pairs.append(("quiet", "TRUE"))
        if kw.get("extra_args"):
            raise RuntimeError("quant 不支持 extra_args（参数已结构化，如需扩展请改 run_quantifypolya.R）")

        params.write_text("".join(f"{k}\t{v}\n" for k, v in pairs), encoding="utf-8")
        return [rscript, str(self._driver()), str(params)]


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="quantifypolya-skill",
        description="QuantifyPolyA native 技能驱动（Rscript 调用 run_quantifypolya.R）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pq = sub.add_parser("quant", help=SUBCOMMANDS["quant"])
    src = pq.add_mutually_exclusive_group(required=True)
    src.add_argument("--bed-dir", help="含每样本一个 .bed 的目录（文件名去 .bed 即样本名）")
    src.add_argument("--bed-files", help="逗号分隔的 BED 文件列表（与 --bed-dir 二选一）")
    pq.add_argument("--outdir", required=True, help="输出目录（polyA_sites.tsv / apa_<mode>.tsv）")
    pq.add_argument("--fasta", help="基因组 FASTA（可选；执行 Remove.IP 去除内部引发）")
    pq.add_argument("--gff", help="基因注释 GFF3/GTF（可选；Annotate.PolyA，APA 动态度量必需）")
    pq.add_argument("--col-data", help="实验设计表 TSV（首列样本名；须含 condition 列；需与 "
                                       "--contrast 一起启用组间度量）")
    pq.add_argument("--contrast", help="组间对比 <列>,<对照>,<处理>，如 condition,Brain,UHR（默认列 condition）")
    pq.add_argument("--quant-mode", choices=QUANT_MODES, default="canonical",
                    help="APA 动态度量模式（默认 canonical：基因 3'UTR PACs）")
    pq.add_argument("--max-gapwidth", type=int, default=24, help="PAC 聚类最大 gap（默认 24）")
    pq.add_argument("--min-count", type=int, default=None, help="Filter.PolyA 最小计数（需 --gff；默认不过滤）")
    pq.add_argument("--min-sample", type=int, default=None, help="Filter.PolyA 最少样本数（默认 1）")
    pq.add_argument("--save-rds", action="store_true",
                    help="同时保存 QpolyA 对象 outdir/QuantifyPolyA.rds（供 Visualize.PolyA）")
    pq.add_argument("--quiet", action="store_true", help="静默模式（少打印进度）")
    _add_runtime_opts(pq)
    return p


def _threads_arg(value: str) -> int | str:
    """--threads 取值：正整数（pin）或 auto（不写 threads 键，由 R 驱动自动检测）。"""
    v = str(value).strip().lower()
    if v == "auto":
        return "auto"
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数")
    if n < 1:
        raise argparse.ArgumentTypeError("--threads 需为 auto 或正整数（收到: %r）" % value)
    return n


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=_threads_arg, default=None,
                   help="线程数：auto（默认，R 驱动按物理核数-1 检测，供 Cluster.PolyA mc.cores）或正整数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（存放 params.tsv）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = QuantifyPolyASkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = QuantifyPolyASkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

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
