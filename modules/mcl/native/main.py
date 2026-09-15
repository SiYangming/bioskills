#!/usr/bin/env python3
"""mcl native 标准入口驱动。

MCL（Markov Cluster Algorithm，Stijn van Dongen）图聚类：用两路矩阵运算模拟随机流，
单参数 -I（inflation）控制聚类粒度。是 OrthoMCL 同源基因聚类的聚类内核
（mcl mclInput --abc -I 1.5 -o mclOutput）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py cluster mclInput --abc -I 1.5 -o mclOutput --threads 8
   python main.py dump graph.mci -imx graph.mci -o graph.abc --tab labels.txt
   python main.py version
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  cluster  mcl <graph> [--abc] [-I <infl>] -o <out> [-te <threads>] [-scheme N] [-tf spec] [-pi num]
  dump     mcxdump -imx <matrix> -o <out> [-tab <labels>] [--dump-pairs|--dump-lines] [--no-values]
  version  mcl --version
cluster 以 -te 注入线程（MCL 的 expansion threads），线程优先级 --threads > per_subcommand_threads > default_cpus。
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
    "cluster": "MCL 图聚类：mcl <graph> [--abc] -I <infl> -o <out> -te <threads>",
    "dump": "mcxdump 图格式转换：mcxdump -imx <matrix> -o <out> [-tab <labels>]",
    "version": "打印 MCL 版本（mcl --version）",
}

# 子命令 -> 可执行文件名（cluster 用 mcl，dump 用 mcxdump，同属 MCL 套件）
_BINARIES = {"cluster": "mcl", "dump": "mcxdump", "version": "mcl"}


class MclSkill(base.SkillBase):
    software = "mcl"
    binary = "mcl"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_sub_binary(self, subcommand: str) -> str:
        """按子命令惰性解析可执行文件（mcl / mcxdump），找不到会抛错。"""
        try:
            bin_name = _BINARIES[subcommand]
        except KeyError:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 MCL"
                f"（mamba create -n mcl-native -c conda-forge -c bioconda mcl=14.137）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 mcl / mcxdump 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise RuntimeError(f"未知子命令: {subcommand}（支持: {', '.join(SUBCOMMANDS)}）")

        bin_path = self._resolve_sub_binary(subcommand)

        if subcommand == "cluster":
            return self._build_cluster(bin_path, **kw)
        if subcommand == "dump":
            return self._build_dump(bin_path, **kw)
        return [bin_path, "--version"]

    # -- cluster（mcl） ----------------------------------------------------- #
    def _build_cluster(self, bin_path: str, **kw) -> list[str]:
        graph = kw.get("graph") or kw.get("input")
        if not graph:
            raise RuntimeError("cluster 缺少必填参数 graph（输入图文件，ABC 或原生矩阵格式）")
        output = kw.get("output")
        if not output:
            raise RuntimeError("cluster 缺少必填参数 output（-o 聚类结果文件）")

        cmd: list[str] = [bin_path, str(graph)]
        if kw.get("abc"):
            cmd.append("--abc")
        if kw.get("inflation") is not None:
            cmd += ["-I", str(kw["inflation"])]
        cmd += ["-o", str(output)]
        threads = self._effective_threads("cluster", kw.get("threads"))
        if threads and threads > 0:
            cmd += ["-te", str(threads)]
        if kw.get("scheme") is not None:
            cmd += ["-scheme", str(kw["scheme"])]
        if kw.get("tf"):
            cmd += ["-tf", str(kw["tf"])]
        if kw.get("pre_inflation") is not None:
            cmd += ["-pi", str(kw["pre_inflation"])]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- dump（mcxdump） ---------------------------------------------------- #
    def _build_dump(self, bin_path: str, **kw) -> list[str]:
        matrix = kw.get("matrix") or kw.get("input")
        if not matrix:
            raise RuntimeError("dump 缺少必填参数 matrix（-imx 输入矩阵文件）")
        output = kw.get("output")
        if not output:
            raise RuntimeError("dump 缺少必填参数 output（-o 输出文件）")

        cmd: list[str] = [bin_path, "-imx", str(matrix), "-o", str(output)]
        if kw.get("tab"):
            cmd += ["-tab", str(kw["tab"])]
        if kw.get("dump_pairs"):
            cmd.append("--dump-pairs")
        if kw.get("no_values"):
            cmd.append("--no-values")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（与 stringtie/samtools 一致：真实执行，找不到二进制抛错）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="mcl-skill",
        description="mcl native 技能驱动（MCL 图聚类，自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # cluster
    pc = sub.add_parser("cluster", help=SUBCOMMANDS["cluster"])
    pc.add_argument("input", nargs="?", help="输入图文件（别名 --graph）")
    pc.add_argument("--graph", help="输入图的别名")
    pc.add_argument("--abc", action="store_true", help="输入为 ABC 标签格式（每行 标签A 标签B 权重）")
    pc.add_argument("-I", "--inflation", type=float, help="MCL inflation 参数（默认 2.0；OrthoMCL 常用 1.5）")
    pc.add_argument("-scheme", type=int, help="资源/剪枝方案编号（大图调优用）")
    pc.add_argument("-tf", dest="tf", help="输入矩阵变换表达式（如 'gq(0.7),add(-0.7)'）")
    pc.add_argument("-pi", "--pre-inflation", type=float, help="预膨胀参数")
    pc.add_argument("-o", "--output", help="输出聚类结果文件")
    pc.add_argument("--extra-args", help="透传给 mcl 的额外参数")
    _add_runtime_opts(pc)

    # dump
    pd = sub.add_parser("dump", help=SUBCOMMANDS["dump"])
    pd.add_argument("input", nargs="?", help="输入矩阵文件（别名 --matrix）")
    pd.add_argument("--matrix", "-imx", help="输入矩阵文件的别名（对应 mcxdump -imx）")
    pd.add_argument("-o", "--output", help="输出文件")
    pd.add_argument("-tab", "--tab", help="标签文件（索引 -> 标签）")
    pd.add_argument("--dump-pairs", action="store_true", help="逐条输出矩阵条目（--dump-pairs）")
    pd.add_argument("--no-values", action="store_true", help="省略权重值（--no-values）")
    pd.add_argument("--extra-args", help="透传给 mcxdump 的额外参数")
    _add_runtime_opts(pd)

    # version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（cluster 以 -te 注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = MclSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MclSkill()
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
