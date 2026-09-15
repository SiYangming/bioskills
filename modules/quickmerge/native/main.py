#!/usr/bin/env python3
"""quickmerge native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py nucmer ref.fasta qry.fasta -p out
   python main.py para_nucmer ref.fasta qry.fasta --CPU 8 --nucmer-args " -p out -l 100" -o out.delta
   python main.py delta_filter out.delta -i 95 -r -q -o out.rq.delta
   python main.py quickmerge -d out.rq.delta -q qry.fasta -r ref.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐文档 04.md「19. quickmerge」）：
  nucmer        nucmer [--threads N] [-p out] [-c 200] <ref> <qry>
  para_nucmer   para_nucmer --CPU N --nucmer " <nucmer opts>" <ref> <qry>   （delta 写 stdout）
  delta_filter  delta-filter [-i 95] [-r] [-q] <delta>                       （写 stdout）
  quickmerge    quickmerge -d <delta> -q <qry> -r <ref> [-hco 5.0] [-c 1.5] [-l 100000] [-ml 5000] [-p out]
quickmerge 依赖 MUMmer 的 nucmer / delta-filter；官方 conda 包会自动带入 MUMmer 依赖。
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus。
二进制惰性解析：测试通过 monkeypatch _resolve_binary 验证 argv 构造，不依赖工具已安装。
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
    "nucmer": "MUMmer 比对（nucmer）-> <prefix>.delta",
    "para_nucmer": "MUMmer 并行比对（para_nucmer --CPU N）-> out.delta（stdout）",
    "delta_filter": "过滤 delta（delta-filter -i 95 -r -q）-> out.rq.delta（stdout）",
    "quickmerge": "合并组装（quickmerge）-> <prefix>_out.fasta",
}

# 子命令 -> 官方可执行名（delta-filter 官方带连字符）
BINARY_BY_SUBCOMMAND = {
    "nucmer": "nucmer",
    "para_nucmer": "para_nucmer",
    "delta_filter": "delta-filter",
    "quickmerge": "quickmerge",
}

# 子命令 -> 结果写 stdout（由 main() 重定向到 --output）
STDOUT_SUBCOMMANDS = {"para_nucmer", "delta_filter"}


class QuickmergeSkill(base.SkillBase):
    software = "quickmerge"
    binary = "quickmerge"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令惰性解析官方可执行文件（nucmer / para_nucmer / delta-filter / quickmerge）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 quickmerge（含 MUMmer）。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 quickmerge 四步链路命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(BINARY_BY_SUBCOMMAND[subcommand])
        cmd: list[str] = [binary]

        if subcommand == "nucmer":
            ref, qry = kw.get("reference"), kw.get("query")
            if not (ref and qry):
                raise ValueError("nucmer 需要 reference 与 query 两个输入")
            if kw.get("prefix"):
                cmd += ["-p", str(kw["prefix"])]
            if kw.get("min_cluster") is not None:
                cmd += ["-c", str(kw["min_cluster"])]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--threads", str(threads)]
            cmd += [str(ref), str(qry)]

        elif subcommand == "para_nucmer":
            ref, qry = kw.get("reference"), kw.get("query")
            if not (ref and qry):
                raise ValueError("para_nucmer 需要 reference 与 query 两个输入")
            cpu = kw.get("cpu") or self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--CPU", str(cpu)]
            if kw.get("nucmer_args"):
                cmd += ["--nucmer", str(kw["nucmer_args"])]
            cmd += [str(ref), str(qry)]

        elif subcommand == "delta_filter":
            delta = kw.get("delta")
            if not delta:
                raise ValueError("delta_filter 需要 delta（输入 .delta 文件）")
            if kw.get("min_similarity") is not None:
                cmd += ["-i", str(kw["min_similarity"])]
            if kw.get("filter_ref"):
                cmd.append("-r")
            if kw.get("filter_query"):
                cmd.append("-q")
            cmd.append(str(delta))

        elif subcommand == "quickmerge":
            delta, qry, ref = kw.get("delta"), kw.get("query"), kw.get("reference")
            if not (delta and qry and ref):
                raise ValueError("quickmerge 需要 --delta / --query / --reference")
            cmd += ["-d", str(delta), "-q", str(qry), "-r", str(ref)]
            if kw.get("hco") is not None:
                cmd += ["-hco", str(kw["hco"])]
            if kw.get("coverage") is not None:
                cmd += ["-c", str(kw["coverage"])]
            if kw.get("min_length") is not None:
                cmd += ["-l", str(kw["min_length"])]
            if kw.get("min_overlap") is not None:
                cmd += ["-ml", str(kw["min_overlap"])]
            cmd += ["-p", str(kw.get("prefix") or "out")]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 由 main() 统一处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="quickmerge-skill",
        description="quickmerge native 技能驱动（nucmer / para_nucmer / delta-filter / quickmerge）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # nucmer
    pn = sub.add_parser("nucmer", help=SUBCOMMANDS["nucmer"])
    pn.add_argument("reference", help="参考组装 FASTA")
    pn.add_argument("query", help="查询组装 FASTA")
    pn.add_argument("-p", "--prefix", help="输出前缀（默认 out -> out.delta）")
    pn.add_argument("-c", "--min-cluster", dest="min_cluster", type=int, help="最小匹配簇长度")
    pn.add_argument("--extra-args", help="透传给 nucmer 的额外参数")
    _add_runtime_opts(pn)

    # para_nucmer
    pp = sub.add_parser("para_nucmer", help=SUBCOMMANDS["para_nucmer"])
    pp.add_argument("reference", help="参考组装 FASTA")
    pp.add_argument("query", help="查询组装 FASTA")
    pp.add_argument("--CPU", dest="cpu", type=int, help="并行核数（默认取线程优先级结果）")
    pp.add_argument("--nucmer-args", dest="nucmer_args", help="透传给内部 nucmer 的参数字符串（如 ' -p out -l 100'）")
    pp.add_argument("-o", "--output", help="把 stdout delta 写入该文件")
    pp.add_argument("--extra-args", help="透传给 para_nucmer 的额外参数")
    _add_runtime_opts(pp)

    # delta_filter
    pf = sub.add_parser("delta_filter", help=SUBCOMMANDS["delta_filter"])
    pf.add_argument("delta", help="输入 .delta 文件")
    pf.add_argument("-i", "--min-similarity", dest="min_similarity", type=float, help="最小相似度（如 95）")
    pf.add_argument("-r", "--filter-ref", dest="filter_ref", action="store_true", help="保留参考序列最佳匹配")
    pf.add_argument("-q", "--filter-query", dest="filter_query", action="store_true", help="保留查询序列最佳匹配")
    pf.add_argument("-o", "--output", help="把 stdout delta 写入该文件")
    pf.add_argument("--extra-args", help="透传给 delta-filter 的额外参数")
    _add_runtime_opts(pf)

    # quickmerge
    pq = sub.add_parser("quickmerge", help=SUBCOMMANDS["quickmerge"])
    pq.add_argument("-d", "--delta", required=True, help="过滤后的 delta 文件")
    pq.add_argument("-q", "--query", required=True, help="查询组装 FASTA")
    pq.add_argument("-r", "--reference", required=True, help="参考组装 FASTA")
    pq.add_argument("-hco", type=float, help="同源性截止值（默认 5.0）")
    pq.add_argument("-c", "--coverage", type=float, help="覆盖度阈值（默认 1.5）")
    pq.add_argument("-l", "--min-length", dest="min_length", type=int, help="最小序列长度（默认 100000）")
    pq.add_argument("-ml", "--min-overlap", dest="min_overlap", type=int, help="最小重叠长度（默认 5000）")
    pq.add_argument("-p", "--prefix", help="输出前缀（默认 out -> out_out.fasta）")
    pq.add_argument("--extra-args", help="透传给 quickmerge 的额外参数")
    _add_runtime_opts(pq)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（nucmer --threads / para_nucmer --CPU）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = QuickmergeSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = QuickmergeSkill()
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

    # 写 stdout 的子命令：若提供 output，则把 stdout 落到 output 文件
    if ns.subcommand in STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
