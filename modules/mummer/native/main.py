#!/usr/bin/env python3
"""MUMmer v4 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py nucmer ref.fasta qry.fasta -p out -c 200 -g 200 --threads 8
   python main.py para_nucmer ref.fasta qry.fasta --CPU 8 --nucmer-args " -p out -l 100" -o out.delta
   python main.py delta_filter out.delta -i 95 -r -q -o out.rq.delta
   python main.py show_coords out.rq.delta -c -d -l -I 95 -L 10000 -r -o out.show
   python main.py mummerplot out.delta -f -l -p out -s large -t png
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  nucmer        nucmer [--threads N] [-p out] [-c 200] [-g 200] <ref> <qry>
  para_nucmer   para_nucmer --CPU N --nucmer " <nucmer opts>" <ref> <qry>   （delta 写 stdout）
  delta_filter  delta-filter [-i 95] [-r] [-q] <delta>                       （写 stdout）
  show_coords   show-coords [-c] [-d] [-l] [-I 95] [-L 10000] [-r] <delta>   （写 stdout）
  mummerplot    mummerplot [-f] [-l] [-p out] [-s large] [-t png] [-r sub] [-S] <delta>
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
    "nucmer": "全基因组比对（nucmer）-> <prefix>.delta",
    "para_nucmer": "并行全基因组比对（para_nucmer --CPU N）-> out.delta（stdout）",
    "delta_filter": "过滤 delta 比对结果（delta-filter -i 95 -r -q）-> out.rq.delta（stdout）",
    "show_coords": "展示比对坐标/相似度/覆盖率（show-coords -c -d -l）-> out.show（stdout）",
    "mummerplot": "gnuplot 点阵图（mummerplot -f -l -p out -s large -t png）-> out.png",
}

# 子命令 -> 官方可执行名（delta-filter / show-coords 官方带连字符）
BINARY_BY_SUBCOMMAND = {
    "nucmer": "nucmer",
    "para_nucmer": "para_nucmer",
    "delta_filter": "delta-filter",
    "show_coords": "show-coords",
    "mummerplot": "mummerplot",
}

# 子命令 -> 结果写 stdout（由 main() 重定向到 --output）
STDOUT_SUBCOMMANDS = {"para_nucmer", "delta_filter", "show_coords"}


class MummerSkill(base.SkillBase):
    software = "mummer"
    binary = "nucmer"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令惰性解析官方可执行文件（nucmer / para_nucmer / delta-filter / show-coords / mummerplot）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 MUMmer。"
            )
        return path

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 MUMmer 命令行。"""
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
            if kw.get("max_gap") is not None:
                cmd += ["-g", str(kw["max_gap"])]
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--threads", str(threads)]
            cmd += [str(ref), str(qry)]

        elif subcommand == "para_nucmer":
            ref, qry = kw.get("reference"), kw.get("query")
            if not (ref and qry):
                raise ValueError("para_nucmer 需要 reference 与 query 两个输入")
            cpu = kw.get("cpu") or self._effective_threads(subcommand, kw.get("threads"))
            cmd += ["--CPU", str(cpu)]
            nuc_args = kw.get("nucmer_args")
            if nuc_args:
                cmd += ["--nucmer", str(nuc_args)]
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

        elif subcommand == "show_coords":
            delta = kw.get("delta")
            if not delta:
                raise ValueError("show_coords 需要 delta（输入 .delta 文件）")
            if kw.get("show_coverage", True):
                cmd.append("-c")
            if kw.get("show_diffs", True):
                cmd.append("-d")
            if kw.get("show_length", True):
                cmd.append("-l")
            if kw.get("min_identity") is not None:
                cmd += ["-I", str(kw["min_identity"])]
            if kw.get("min_align_len") is not None:
                cmd += ["-L", str(kw["min_align_len"])]
            if kw.get("sort_ref"):
                cmd.append("-r")
            cmd.append(str(delta))

        elif subcommand == "mummerplot":
            delta = kw.get("delta")
            if not delta:
                raise ValueError("mummerplot 需要 delta（输入 .delta 文件）")
            if kw.get("plot_filter", True):
                cmd.append("-f")
            if kw.get("plot_label", True):
                cmd.append("-l")
            if kw.get("prefix"):
                cmd += ["-p", str(kw["prefix"])]
            if kw.get("plot_size"):
                cmd += ["-s", str(kw["plot_size"])]
            if kw.get("plot_terminal"):
                cmd += ["-t", str(kw["plot_terminal"])]
            if kw.get("plot_scaffold"):
                cmd += ["-r", str(kw["plot_scaffold"])]
            if kw.get("plot_symmetric"):
                cmd.append("-S")
            cmd.append(str(delta))

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
        prog="mummer-skill",
        description="MUMmer v4 native 技能驱动（nucmer / para_nucmer / delta-filter / show-coords / mummerplot）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # nucmer
    pn = sub.add_parser("nucmer", help=SUBCOMMANDS["nucmer"])
    pn.add_argument("reference", help="参考序列 FASTA")
    pn.add_argument("query", help="查询序列 FASTA")
    pn.add_argument("-p", "--prefix", help="输出前缀（默认 out -> out.delta）")
    pn.add_argument("-c", "--min-cluster", dest="min_cluster", type=int, help="最小匹配簇长度（默认自动）")
    pn.add_argument("-g", "--max-gap", dest="max_gap", type=int, help="最大 gap 长度（默认自动）")
    pn.add_argument("--extra-args", help="透传给 nucmer 的额外参数")
    _add_runtime_opts(pn)

    # para_nucmer
    pp = sub.add_parser("para_nucmer", help=SUBCOMMANDS["para_nucmer"])
    pp.add_argument("reference", help="参考序列 FASTA")
    pp.add_argument("query", help="查询序列 FASTA")
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

    # show_coords
    pc = sub.add_parser("show_coords", help=SUBCOMMANDS["show_coords"])
    pc.add_argument("delta", help="输入 .delta 文件")
    pc.add_argument("-c", dest="show_coverage", action="store_true", default=True, help="显示覆盖率（默认开）")
    pc.add_argument("--no-coverage", dest="show_coverage", action="store_false", help="关闭 -c")
    pc.add_argument("-d", dest="show_diffs", action="store_true", default=True, help="显示差异数（默认开）")
    pc.add_argument("--no-diffs", dest="show_diffs", action="store_false", help="关闭 -d")
    pc.add_argument("-l", dest="show_length", action="store_true", default=True, help="显示比对长度（默认开）")
    pc.add_argument("--no-length", dest="show_length", action="store_false", help="关闭 -l")
    pc.add_argument("-I", "--min-identity", dest="min_identity", type=int, help="最小相似度（如 95）")
    pc.add_argument("-L", "--min-align-len", dest="min_align_len", type=int, help="最小比对长度（如 10000）")
    pc.add_argument("-r", "--sort-ref", dest="sort_ref", action="store_true", help="按参考序列排序")
    pc.add_argument("-o", "--output", help="把 stdout 坐标表写入该文件")
    pc.add_argument("--extra-args", help="透传给 show-coords 的额外参数")
    _add_runtime_opts(pc)

    # mummerplot
    pm = sub.add_parser("mummerplot", help=SUBCOMMANDS["mummerplot"])
    pm.add_argument("delta", help="输入 .delta 文件")
    pm.add_argument("-f", dest="plot_filter", action="store_true", default=True, help="使用过滤后的 delta（默认开）")
    pm.add_argument("--no-filter", dest="plot_filter", action="store_false", help="关闭 -f")
    pm.add_argument("-l", dest="plot_label", action="store_true", default=True, help="显示标签（默认开）")
    pm.add_argument("--no-label", dest="plot_label", action="store_false", help="关闭 -l")
    pm.add_argument("-p", "--prefix", help="输出前缀（默认 out -> out.png/out.gp）")
    pm.add_argument("-s", "--plot-size", dest="plot_size", help="图尺寸（如 large）")
    pm.add_argument("-t", "--plot-terminal", dest="plot_terminal", help="输出终端类型（如 png）")
    pm.add_argument("-r", "--plot-scaffold", dest="plot_scaffold", help="仅可视化指定 scaffold")
    pm.add_argument("-S", "--plot-symmetric", dest="plot_symmetric", action="store_true", help="生成对称点阵图")
    pm.add_argument("--extra-args", help="透传给 mummerplot 的额外参数")
    _add_runtime_opts(pm)

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
        skill = MummerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MummerSkill()
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
