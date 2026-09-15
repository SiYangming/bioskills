#!/usr/bin/env python3
"""microbiomeutil native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py chimeraslayer --query-nast q.NAST --db-nast ref.NAST --db-fasta ref.fasta
   python main.py nastier --query-fasta seqs.fasta --num-top-hits 10
   python main.py wigeon --query-nast q.NAST
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（每个子命令对应 microbiomeutil 的一个 Perl/C 程序）：
  chimeraslayer   ChimeraSlayer.pl --query_NAST <q> [--db_NAST <r> --db_FASTA <r>] [-n N -R X -P N ...]
  nastier         run_NAST-iEr.pl --query_FASTA <q> [--db_NAST <r> --db_FASTA <r> --num_top_hits N --Evalue E]
  wigeon          run_WigeoN.pl --query_NAST <q> [--db_NAST <r> --db_FASTA <r> --num_top_hits N --plot]

说明：microbiomeutil 三个程序均为单线程；--threads 作为契约字段被接受但不注入命令行。
上游 Perl 脚本使用 FindBin 定位自身目录，建议在脚本所在目录或其父目录下运行，
或通过 --exec-dir 指定工作目录（见 README「注意」）。
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
    "chimeraslayer": "ChimeraSlayer.pl：基于 BLAST 的 16S 嵌合体检测（需 NAST 比对格式输入）",
    "nastier": "run_NAST-iEr.pl：把未比对序列转换为 NAST 比对格式（新建参考 NAST 比对）",
    "wigeon": "run_WigeoN.pl：Pintail 类 16S 序列异常（含嵌合）检测（NAST 格式输入）",
}

# 子命令 -> 对应的可执行程序（安装后位于 PATH）
SCRIPT_BY_SUBCOMMAND = {
    "chimeraslayer": "ChimeraSlayer.pl",
    "nastier": "run_NAST-iEr.pl",
    "wigeon": "run_WigeoN.pl",
}


class MicrobiomeutilSkill(base.SkillBase):
    software = "microbiomeutil"
    binary = "ChimeraSlayer.pl"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（microbiomeutil 单线程，仅契约记录）。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_binary_for(self, subcommand: str) -> str:
        """按子命令惰性解析对应可执行程序（找不到抛错；测试可 monkeypatch）。"""
        name = SCRIPT_BY_SUBCOMMAND.get(subcommand)
        if not name:
            raise ValueError(f"未知子命令: {subcommand}")
        if name == (self.binary or self.software):
            return self._resolve_binary()
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到可执行程序 '{name}'，请先通过 native/install.sh 或自建容器安装 microbiomeutil。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 microbiomeutil 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary_for(subcommand)
        self._effective_threads(subcommand, kw.get("threads"))  # 契约线程（不注入）

        if subcommand == "chimeraslayer":
            query = kw.get("query_nast")
            if not query:
                raise ValueError("chimeraslayer 缺少必填参数 query_nast（NAST 比对格式的查询 FASTA）")
            cmd: list[str] = [binary, "--query_NAST", str(query)]
            if kw.get("db_nast"):
                cmd += ["--db_NAST", str(kw["db_nast"])]
            if kw.get("db_fasta"):
                cmd += ["--db_FASTA", str(kw["db_fasta"])]
            if kw.get("exec_dir"):
                cmd += ["--exec_dir", str(kw["exec_dir"])]
            if kw.get("num_db_seqs") is not None:
                cmd += ["-n", str(kw["num_db_seqs"])]
            if kw.get("min_div_ratio") is not None:
                cmd += ["-R", str(kw["min_div_ratio"])]
            if kw.get("min_pct_id") is not None:
                cmd += ["-P", str(kw["min_pct_id"])]
            if kw.get("match_score") is not None:
                cmd += ["-M", str(kw["match_score"])]
            if kw.get("mismatch_penalty") is not None:
                cmd += ["-N", str(kw["mismatch_penalty"])]
            if kw.get("min_query_cov") is not None:
                cmd += ["-Q", str(kw["min_query_cov"])]
            if kw.get("max_traverses") is not None:
                cmd += ["-T", str(kw["max_traverses"])]
            if kw.get("window_size") is not None:
                cmd += ["--windowSize", str(kw["window_size"])]
            if kw.get("window_step") is not None:
                cmd += ["--windowStep", str(kw["window_step"])]
            if kw.get("min_bs") is not None:
                cmd += ["--minBS", str(kw["min_bs"])]
            if kw.get("num_bs_replicates") is not None:
                cmd += ["--num_BS_replicates", str(kw["num_bs_replicates"])]
            if kw.get("low_range_finer_bs") is not None:
                cmd += ["--low_range_finer_BS", str(kw["low_range_finer_bs"])]
            if kw.get("num_finer_bs_replicates") is not None:
                cmd += ["--num_finer_BS_replicates", str(kw["num_finer_bs_replicates"])]
            if kw.get("snp_sample_pct") is not None:
                cmd += ["-S", str(kw["snp_sample_pct"])]
            if kw.get("num_parents_test") is not None:
                cmd += ["--num_parents_test", str(kw["num_parents_test"])]
            if kw.get("max_chimera_parent_per_id") is not None:
                cmd += ["--MAX_CHIMERA_PARENT_PER_ID", str(kw["max_chimera_parent_per_id"])]
            if kw.get("print_final_alignments"):
                cmd.append("--printFinalAlignments")
            if kw.get("print_cs_alignments"):
                cmd.append("--printCSalignments")

        elif subcommand == "nastier":
            query = kw.get("query_fasta")
            if not query:
                raise ValueError("nastier 缺少必填参数 query_fasta（待 NAST 比对的 FASTA）")
            cmd = [binary, "--query_FASTA", str(query)]
            if kw.get("db_nast"):
                cmd += ["--db_NAST", str(kw["db_nast"])]
            if kw.get("db_fasta"):
                cmd += ["--db_FASTA", str(kw["db_fasta"])]
            if kw.get("num_top_hits") is not None:
                cmd += ["--num_top_hits", str(kw["num_top_hits"])]
            if kw.get("evalue") is not None:
                cmd += ["--Evalue", str(kw["evalue"])]

        else:  # wigeon
            query = kw.get("query_nast")
            if not query:
                raise ValueError("wigeon 缺少必填参数 query_nast（NAST 比对格式的查询 FASTA）")
            cmd = [binary, "--query_NAST", str(query)]
            if kw.get("db_nast"):
                cmd += ["--db_NAST", str(kw["db_nast"])]
            if kw.get("db_fasta"):
                cmd += ["--db_FASTA", str(kw["db_fasta"])]
            if kw.get("num_top_hits") is not None:
                cmd += ["--num_top_hits", str(kw["num_top_hits"])]
            if kw.get("exec_dir"):
                cmd += ["--exec_dir", str(kw["exec_dir"])]
            if kw.get("plot"):
                cmd.append("--plot")
            if kw.get("debug"):
                cmd.append("--DEBUG")

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
        prog="microbiomeutil-skill",
        description="microbiomeutil native 技能驱动（ChimeraSlayer / NAST-iEr / WigeoN）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # chimeraslayer
    pc = sub.add_parser("chimeraslayer", help=SUBCOMMANDS["chimeraslayer"])
    pc.add_argument("--query-nast", required=True, help="查询序列（NAST 比对格式 FASTA）")
    pc.add_argument("--db-nast", help="参考库 NAST 比对格式 FASTA（默认随包 RESOURCES）")
    pc.add_argument("--db-fasta", help="参考库 FASTA（megablast 已格式化，默认随包 RESOURCES）")
    pc.add_argument("--exec-dir", help="运行前 chdir 到此目录（Perl FindBin 依赖）")
    pc.add_argument("-n", "--num-db-seqs", type=int, help="参与比较的 top N 参考序列（默认 15）")
    pc.add_argument("-R", "--min-div-ratio", type=float, help="最小 divergence ratio（默认 1.007）")
    pc.add_argument("-P", "--min-pct-id", type=float, help="匹配序列最小百分比一致性（默认 90）")
    pc.add_argument("-M", "--match-score", type=int, help="匹配得分（默认 +5）")
    pc.add_argument("-N", "--mismatch-penalty", type=int, help="错配罚分（默认 -4）")
    pc.add_argument("-Q", "--min-query-cov", type=float, help="参考序列最小查询覆盖度（默认 70）")
    pc.add_argument("-T", "--max-traverses", type=int, help="多重比对最大遍历次数（默认 1）")
    pc.add_argument("--window-size", type=int, help="ChimeraPhyloChecker 窗口大小（默认 50）")
    pc.add_argument("--window-step", type=int, help="窗口步长（默认 5）")
    pc.add_argument("--min-bs", type=float, help="判定嵌合体的最小 bootstrap 支持（默认 90）")
    pc.add_argument("--num-bs-replicates", type=int, help="bootstrap 重复数（默认 100）")
    pc.add_argument("--low-range-finer-bs", type=float, help="更精细 bootstrap 的低区间（默认 10）")
    pc.add_argument("--num-finer-bs-replicates", type=int, help="更精细 bootstrap 重复数（默认 1000）")
    pc.add_argument("-S", "--snp-sample-pct", type=float, help="断点两侧采样 SNP 百分比（默认 10）")
    pc.add_argument("--num-parents-test", type=int, help="待测潜在亲本数（默认 3）")
    pc.add_argument("--max-chimera-parent-per-id", type=int, help="超过此 perID 视为非嵌合（默认 100）")
    pc.add_argument("--print-final-alignments", action="store_true", help="输出 query 与候选亲本比对")
    pc.add_argument("--print-cs-alignments", action="store_true", help="输出 ChimeraSlayer 比对")
    pc.add_argument("--extra-args", help="透传给 ChimeraSlayer.pl 的额外参数")
    _add_runtime_opts(pc)

    # nastier
    pn = sub.add_parser("nastier", help=SUBCOMMANDS["nastier"])
    pn.add_argument("--query-fasta", required=True, help="待 NAST 比对的查询 FASTA")
    pn.add_argument("--db-nast", help="参考库 NAST 比对格式 FASTA（默认随包 RESOURCES）")
    pn.add_argument("--db-fasta", help="参考库 FASTA（默认随包 RESOURCES）")
    pn.add_argument("--num-top-hits", type=int, help="用于 profile 比对的 top hits 数（默认 10）")
    pn.add_argument("--evalue", help="top hits 的 E-value 阈值（默认 1e-50）")
    pn.add_argument("--extra-args", help="透传给 run_NAST-iEr.pl 的额外参数")
    _add_runtime_opts(pn)

    # wigeon
    pw = sub.add_parser("wigeon", help=SUBCOMMANDS["wigeon"])
    pw.add_argument("--query-nast", required=True, help="查询序列（NAST 比对格式 FASTA）")
    pw.add_argument("--db-nast", help="参考库 NAST 比对格式 FASTA（默认随包 RESOURCES）")
    pw.add_argument("--db-fasta", help="参考库 FASTA（默认随包 RESOURCES）")
    pw.add_argument("--num-top-hits", type=int, help="使用的 top hits 数（默认 1，仅最佳匹配）")
    pw.add_argument("--exec-dir", help="运行前 chdir 到此目录")
    pw.add_argument("--plot", action="store_true", help="生成绘图输出")
    pw.add_argument("--debug", action="store_true", help="调试输出（--DEBUG）")
    pw.add_argument("--extra-args", help="透传给 run_WigeoN.pl 的额外参数")
    _add_runtime_opts(pw)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（microbiomeutil 单线程，仅契约字段）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = MicrobiomeutilSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MicrobiomeutilSkill()
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
