#!/usr/bin/env python3
"""dada2 native 标准入口驱动（DADA2 R 包，经 Rscript 调用）。

DADA2 以 R 包形态分发、无独立命令行二进制，本驱动按子命令生成一段 R 脚本
（写入临时目录），再以 `Rscript <script>` 运行，等价于 DADA2 官方 16S 流程：

  filterAndTrim  -> filterAndTrim()   # 质量过滤（5'/3' 端截短、maxEE）
  learnErrors    -> learnErrors()     # 学习测序错误模型
  denoise / dada -> dada()            # 去噪（核心去噪；denoise 与 dada 同义）
  mergePairs     -> mergePairs()      # 双端合并
  makeSequenceTable -> makeSequenceTable()  # 生成 ASV 序列表
  removeBimera   -> removeBimeraDenovo()    # 去嵌合体

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py filterAndTrim sample_R1.fastq.gz --filt sample_R1.filt.fastq.gz \
       --trunc-len 120 --max-ee 2 --threads 8
   python main.py learnErrors --reads sample_R1.filt.fastq.gz --output errF.rds --threads 8
   python main.py denoise --reads sample_R1.filt.fastq.gz --error errF.rds \
       --output dadaF.rds --threads 8
   python main.py makeSequenceTable merged.rds --output seqtab.rds
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入多线程（DADA2 multithread）与临时目录优化。
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
    "filterAndTrim": "fastq -> 过滤后 fastq（filterAndTrim：5'/3' 截短 + maxEE + 质量截断）",
    "learnErrors": "过滤后 fastq -> error model RDS（learnErrors）",
    "denoise": "过滤后 fastq + error model -> dada 对象 RDS（dada）",
    "dada": "denoise 的别名（同一 DADA2 去噪核心 dada()）",
    "mergePairs": "成对 dada/fastq -> 合并对象 RDS（mergePairs，双端）",
    "makeSequenceTable": "合并对象 RDS -> ASV 序列表 RDS（makeSequenceTable）",
    "removeBimera": "序列表 RDS -> 去嵌合序列表 RDS（removeBimeraDenovo）",
}


def _rq(value) -> str:
    """把值渲染为 R 单引号字符串字面量（转义反斜杠与单引号）。"""
    s = str(value)
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def _rvec(values) -> str:
    """把可迭代值渲染为 R 向量 c(...)。"""
    return "c(" + ", ".join(_rq(v) for v in values) + ")"


def _split_list(value) -> list[str]:
    """把逗号分隔字符串（或列表）拆为路径列表。"""
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value]
    return [p.strip() for p in str(value).split(",") if p.strip()]


class Dada2Skill(base.SkillBase):
    software = "dada2"
    binary = "Rscript"

    # -- 脚本生成 ----------------------------------------------------------- #
    def _write_script(self, subcommand: str, body: str) -> Path:
        script_dir = Path(self.make_tmpdir("dada2_"))
        script = script_dir / f"{subcommand}.R"
        script.write_text(body, encoding="utf-8")
        return script

    def _render(self, subcommand: str, threads: int, kw: dict) -> str:
        if subcommand == "filterAndTrim":
            return self._render_filter_and_trim(threads, kw)
        if subcommand == "learnErrors":
            return self._render_learn_errors(threads, kw)
        if subcommand in ("denoise", "dada"):
            return self._render_denoise(threads, kw)
        if subcommand == "mergePairs":
            return self._render_merge_pairs(kw)
        if subcommand == "makeSequenceTable":
            return self._render_make_sequence_table(kw)
        if subcommand == "removeBimera":
            return self._render_remove_bimera(threads, kw)
        raise ValueError(f"未知子命令: {subcommand}")

    def _render_filter_and_trim(self, threads: int, kw: dict) -> str:
        fwd = _split_list(kw.get("input") or kw.get("fwd"))
        filt = _split_list(kw.get("filt"))
        if not fwd:
            raise ValueError("filterAndTrim 缺少输入 fwd（位置参数）")
        if not filt:
            raise ValueError("filterAndTrim 缺少输出 filt（--filt）")
        rev = _split_list(kw.get("rev"))
        filt_rev = _split_list(kw.get("filt_rev"))
        paired = bool(rev)

        trunc = int(kw.get("trunc_len") or 0)
        trim_left = int(kw.get("trim_left") or 0)
        if paired:
            tlf = kw.get("trunc_len_f")
            tlr = kw.get("trunc_len_r")
            tlf = trunc if tlf is None else int(tlf)
            tlr = trunc if tlr is None else int(tlr)
            mlf = kw.get("trim_left_f")
            mlr = kw.get("trim_left_r")
            mlf = trim_left if mlf is None else int(mlf)
            mlr = trim_left if mlr is None else int(mlr)
            trunc_expr = f"c({tlf}, {tlr})"
            trim_expr = f"c({mlf}, {mlr})"
        else:
            trunc_expr = str(trunc)
            trim_expr = str(trim_left)

        lines = [
            "suppressPackageStartupMessages(library(dada2))",
            "out <- dada2::filterAndTrim(",
            f"  fwd = {_rvec(fwd)},",
            f"  filt = {_rvec(filt)},",
        ]
        if paired:
            lines += [
                f"  rev = {_rvec(rev)},",
                f"  filt.rev = {_rvec(filt_rev)},",
            ]
        lines += [
            f"  truncLen = {trunc_expr},",
            f"  trimLeft = {trim_expr},",
            f"  maxEE = {kw.get('max_ee', 2.0)},",
            f"  truncQ = {int(kw.get('trunc_q', 2))},",
            f"  minLen = {int(kw.get('min_len', 20))},",
            "  maxLen = Inf,",
            f"  rm.phix = {'TRUE' if kw.get('rm_phix') else 'FALSE'},",
            "  compress = TRUE,",
            f"  multithread = {threads},",
            "  verbose = TRUE",
            ")",
            'cat(sprintf("filterAndTrim: reads.in=%d reads.out=%d\\n", '
            "sum(out[, 1]), sum(out[, 2])))\n",
        ]
        return "\n".join(lines)

    def _render_learn_errors(self, threads: int, kw: dict) -> str:
        reads = _split_list(kw.get("reads") or kw.get("input"))
        out = kw.get("output")
        if not reads:
            raise ValueError("learnErrors 缺少输入 --reads（过滤后 fastq，逗号分隔）")
        if not out:
            raise ValueError("learnErrors 缺少输出 --output（error model RDS）")
        nbases = kw.get("nbases")
        nbases_expr = str(int(nbases)) if nbases else "1e8"
        return "\n".join([
            "suppressPackageStartupMessages(library(dada2))",
            "err <- dada2::learnErrors(",
            f"  fls = {_rvec(reads)},",
            f"  nbases = {nbases_expr},",
            f"  multithread = {threads},",
            f"  randomize = {'TRUE' if kw.get('randomize', True) else 'FALSE'},",
            "  verbose = 1",
            ")",
            f"saveRDS(err, {_rq(out)})",
            'cat("learnErrors: error model saved\\n")\n',
        ])

    def _render_denoise(self, threads: int, kw: dict) -> str:
        reads = _split_list(kw.get("reads") or kw.get("input"))
        err = kw.get("error")
        out = kw.get("output")
        if not reads:
            raise ValueError("denoise 缺少输入 --reads（过滤后 fastq，逗号分隔）")
        if not err:
            raise ValueError("denoise 缺少 --error（learnErrors 产出的 error model RDS）")
        if not out:
            raise ValueError("denoise 缺少输出 --output（dada 对象 RDS）")
        return "\n".join([
            "suppressPackageStartupMessages(library(dada2))",
            f"err <- readRDS({_rq(err)})",
            "denoised <- dada2::dada(",
            f"  derep = {_rvec(reads)},",
            "  err = err,",
            f"  pool = {'TRUE' if kw.get('pool') else 'FALSE'},",
            f"  selfConsist = {'TRUE' if kw.get('self_consist') else 'FALSE'},",
            f"  multithread = {threads},",
            "  verbose = TRUE",
            ")",
            f"saveRDS(denoised, {_rq(out)})",
            'cat("denoise (dada): saved\\n")\n',
        ])

    def _render_merge_pairs(self, kw: dict) -> str:
        dada_f = kw.get("dada_f")
        dada_r = kw.get("dada_r")
        filt_f = kw.get("filt_f")
        filt_r = kw.get("filt_r")
        out = kw.get("output")
        missing = [n for n, v in (("--dada-f", dada_f), ("--dada-r", dada_r),
                                  ("--filt-f", filt_f), ("--filt-r", filt_r),
                                  ("--output", out)) if not v]
        if missing:
            raise ValueError(f"mergePairs 缺少必填参数: {', '.join(missing)}")
        return "\n".join([
            "suppressPackageStartupMessages(library(dada2))",
            f"dadaF <- readRDS({_rq(dada_f)})",
            f"dadaR <- readRDS({_rq(dada_r)})",
            "mergers <- dada2::mergePairs(",
            "  dadaF = dadaF,",
            f"  derepF = {_rq(filt_f)},",
            "  dadaR = dadaR,",
            f"  derepR = {_rq(filt_r)},",
            f"  minOverlap = {int(kw.get('min_overlap', 12))},",
            f"  maxMismatch = {int(kw.get('max_mismatch', 0))},",
            "  verbose = TRUE",
            ")",
            f"saveRDS(mergers, {_rq(out)})",
            'cat("mergePairs: saved\\n")\n',
        ])

    def _render_make_sequence_table(self, kw: dict) -> str:
        out = kw.get("output")
        if not out:
            raise ValueError("makeSequenceTable 缺少输出 --output（ASV 序列表 RDS）")
        dada_inputs = _split_list(kw.get("dada"))
        if dada_inputs:
            ready = ", ".join(f"readRDS({_rq(p)})" for p in dada_inputs)
            lines = [
                "suppressPackageStartupMessages(library(dada2))",
                f"seqtab <- dada2::makeSequenceTable(list({ready}))",
            ]
        else:
            merged = kw.get("input_rds") or kw.get("input")
            if not merged:
                raise ValueError("makeSequenceTable 缺少输入（合并对象 RDS 位置参数，或 --dada 列表）")
            lines = [
                "suppressPackageStartupMessages(library(dada2))",
                f"mergers <- readRDS({_rq(merged)})",
                "seqtab <- dada2::makeSequenceTable(mergers)",
            ]
        lines += [
            f"saveRDS(seqtab, {_rq(out)})",
            'cat(sprintf("makeSequenceTable: %d ASVs\\n", dim(seqtab)[2]))\n',
        ]
        return "\n".join(lines)

    def _render_remove_bimera(self, threads: int, kw: dict) -> str:
        seqtab = kw.get("input_rds") or kw.get("input")
        out = kw.get("output")
        if not seqtab:
            raise ValueError("removeBimera 缺少输入（ASV 序列表 RDS 位置参数）")
        if not out:
            raise ValueError("removeBimera 缺少输出 --output（去嵌合序列表 RDS）")
        method = kw.get("method", "consensus")
        return "\n".join([
            "suppressPackageStartupMessages(library(dada2))",
            f"seqtab <- readRDS({_rq(seqtab)})",
            "seqtab.nochim <- dada2::removeBimeraDenovo(",
            "  seqtab,",
            f"  method = {_rq(method)},",
            f"  multithread = {threads},",
            "  verbose = TRUE",
            ")",
            f"saveRDS(seqtab.nochim, {_rq(out)})",
            'cat(sprintf("removeBimera: %d ASVs retained\\n", dim(seqtab.nochim)[2]))\n',
        ])

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """生成 R 脚本并返回 argv：`Rscript <script.R>`。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")
        rscript = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))
        body = self._render(subcommand, threads, kw)
        script = self._write_script(subcommand, body)
        return [rscript, str(script)]

    def run(self, subcommand: str, **kwargs):
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（DADA2 multithread）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dada2-skill",
        description="dada2 native 技能驱动（Rscript 生成并运行 DADA2 R 脚本）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # filterAndTrim
    pf = sub.add_parser("filterAndTrim", help=SUBCOMMANDS["filterAndTrim"])
    pf.add_argument("input", nargs="?", help="输入 R1 fastq（可逗号分隔多样本）")
    pf.add_argument("--fwd", help="输入 R1 fastq 的别名")
    pf.add_argument("--filt", help="输出 R1 过滤后 fastq")
    pf.add_argument("--rev", help="双端输入 R2 fastq（可选）")
    pf.add_argument("--filt-rev", help="输出 R2 过滤后 fastq（双端模式）")
    pf.add_argument("--trunc-len", type=int, default=0, help="3' 端截短长度（0=不截短）")
    pf.add_argument("--trunc-len-f", type=int, help="双端 R1 截短长度")
    pf.add_argument("--trunc-len-r", type=int, help="双端 R2 截短长度")
    pf.add_argument("--trim-left", type=int, default=0, help="5' 端截短碱基数（0=不截短）")
    pf.add_argument("--trim-left-f", type=int, help="双端 R1 5' 截短")
    pf.add_argument("--trim-left-r", type=int, help="双端 R2 5' 截短")
    pf.add_argument("--max-ee", type=float, default=2.0, help="最大期望错误数（默认 2）")
    pf.add_argument("--trunc-q", type=int, default=2, help="质量截断阈值（默认 2）")
    pf.add_argument("--min-len", type=int, default=20, help="最小保留长度（默认 20）")
    pf.add_argument("--rm-phix", action="store_true", help="去除 PhiX")
    _add_runtime_opts(pf)

    # learnErrors
    ple = sub.add_parser("learnErrors", help=SUBCOMMANDS["learnErrors"])
    ple.add_argument("--reads", help="过滤后 fastq（逗号分隔）")
    ple.add_argument("--output", help="输出 error model RDS")
    ple.add_argument("--nbases", type=int, help="用于学习的碱基数（默认 1e8）")
    ple.add_argument("--no-randomize", dest="randomize", action="store_false",
                     help="关闭随机抽样（默认 randomize=TRUE）")
    _add_runtime_opts(ple)

    # denoise（dada）+ dada 别名
    for name in ("denoise", "dada"):
        pd = sub.add_parser(name, help=SUBCOMMANDS[name])
        pd.add_argument("--reads", help="过滤后 fastq（逗号分隔）")
        pd.add_argument("--error", help="learnErrors 产出的 error model RDS")
        pd.add_argument("--output", help="输出 dada 对象 RDS")
        pd.add_argument("--pool", action="store_true", help="跨样本合并（pool=TRUE）")
        pd.add_argument("--self-consist", action="store_true", help="自洽迭代（selfConsist=TRUE）")
        _add_runtime_opts(pd)

    # mergePairs
    pm = sub.add_parser("mergePairs", help=SUBCOMMANDS["mergePairs"])
    pm.add_argument("--dada-f", help="正向 dada RDS")
    pm.add_argument("--dada-r", help="反向 dada RDS")
    pm.add_argument("--filt-f", help="正向过滤后 fastq")
    pm.add_argument("--filt-r", help="反向过滤后 fastq")
    pm.add_argument("--output", help="输出合并对象 RDS")
    pm.add_argument("--min-overlap", type=int, default=12, help="最小重叠长度（默认 12）")
    pm.add_argument("--max-mismatch", type=int, default=0, help="最大错配数（默认 0）")
    _add_runtime_opts(pm)

    # makeSequenceTable
    pmk = sub.add_parser("makeSequenceTable", help=SUBCOMMANDS["makeSequenceTable"])
    pmk.add_argument("input", nargs="?", help="合并对象 RDS")
    pmk.add_argument("--output", help="输出 ASV 序列表 RDS")
    pmk.add_argument("--dada", help="dada 对象 RDS 列表（逗号分隔，替代合并对象输入）")
    _add_runtime_opts(pmk)

    # removeBimera
    prb = sub.add_parser("removeBimera", help=SUBCOMMANDS["removeBimera"])
    prb.add_argument("input", help="ASV 序列表 RDS")
    prb.add_argument("--output", help="输出去嵌合序列表 RDS")
    prb.add_argument("--method", choices=["consensus", "pooled", "per-sample"],
                     default="consensus", help="去嵌合方法（默认 consensus）")
    _add_runtime_opts(prb)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = Dada2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Dada2Skill()
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
