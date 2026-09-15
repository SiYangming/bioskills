#!/usr/bin/env python3
"""busco native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -i genome.fasta -m genome -l basidiomycota_odb10 -o busco_out --offline --threads 8
   python main.py list_datasets
   python main.py config config/config.ini my_config.ini
   python main.py plot -wd busco_out -rt specific
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（BUSCO 4.1.2）：
  run            busco -i <input> -o <out> -m <mode> [-l <lineage>] -c N [--offline] [--auto-lineage] ...
  list_datasets  busco --list-datasets
  config         python3 busco_configurator.py <config.ini> <out.ini>
  plot           python3 generate_plot.py -wd <dir> [-rt specific|generic]
busco 主程序经 PATH 解析（_resolve_binary）；busco_configurator.py / generate_plot.py 按
BUSCO_HOME/scripts、BUSCO_HOME/bin、PATH 惰性解析（测试时 monkeypatch）。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "run": "序列 + 谱系数据集 -> 完整性评估（busco -m genome|transcriptome|proteins）",
    "list_datasets": "列出 BUSCO 官方可用谱系数据集（busco --list-datasets）",
    "config": "生成/定制 BUSCO 配置 ini（busco_configurator.py）",
    "plot": "汇总结果可视化（generate_plot.py -wd <dir>）",
}

# 子命令 -> 是否为 python 脚本（脚本名）；run 走 busco 主程序
SCRIPTS = {
    "config": "busco_configurator.py",
    "plot": "generate_plot.py",
}


class BuscoSkill(base.SkillBase):
    software = "busco"
    binary = "busco"

    def _resolve_script(self, name: str) -> str:
        """惰性解析 BUSCO 附属脚本路径（BUSCO_HOME/scripts、BUSCO_HOME/bin、PATH）。"""
        home = os.environ.get("BUSCO_HOME")
        if home:
            for cand in (Path(home) / "scripts" / name, Path(home) / "bin" / name, Path(home) / name):
                if cand.is_file():
                    return str(cand)
        found = base.which(name)
        if found:
            return found
        raise RuntimeError(
            f"未找到 BUSCO 脚本 '{name}'：请先通过 conda（busco）或官方镜像安装，"
            f"或设置 BUSCO_HOME 指向 BUSCO 安装目录。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 BUSCO 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        if subcommand == "list_datasets":
            return [self._resolve_binary(), "--list-datasets"]

        if subcommand == "config":
            script = self._resolve_script(SCRIPTS["config"])
            cfg_in = kw.get("config_in") or kw.get("input")
            cfg_out = kw.get("config_out") or kw.get("output")
            if not cfg_in or not cfg_out:
                raise ValueError("config 缺少必填参数 config_in / config_out（config.ini 输入与输出路径）")
            return [sys.executable, script, str(cfg_in), str(cfg_out)]

        if subcommand == "plot":
            script = self._resolve_script(SCRIPTS["plot"])
            wd = kw.get("plot_dir") or kw.get("workdir")
            if not wd:
                raise ValueError("plot 缺少必填参数 plot_dir（-wd 结果目录）")
            cmd = [sys.executable, script, "-wd", str(wd)]
            if kw.get("plot_type"):
                cmd += ["-rt", str(kw["plot_type"])]
            return cmd

        # run
        binary = self._resolve_binary()
        inp = kw.get("input")
        if not inp:
            raise ValueError("run 缺少必填参数 input（-i 输入序列）")
        mode = kw.get("mode") or "genome"
        lineage = kw.get("lineage")
        if not lineage and not kw.get("auto_lineage"):
            raise ValueError("run 需要 -l lineage（谱系数据集）或 --auto_lineage")
        out_name = kw.get("out_name") or kw.get("output")
        cmd: list[str] = [binary, "-i", str(inp), "-m", str(mode)]
        if lineage:
            cmd += ["-l", str(lineage)]
        if out_name:
            cmd += ["-o", str(out_name)]
        if kw.get("out_path"):
            cmd += ["--out_path", str(kw["out_path"])]
        if kw.get("auto_lineage"):
            cmd.append("--auto-lineage")
        if kw.get("offline"):
            cmd.append("--offline")
        if kw.get("force"):
            cmd.append("-f")
        cmd += ["-c", str(self._effective_threads(subcommand, kw.get("threads")))]

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
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="busco-skill",
        description="busco native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-i", "--input", help="输入序列（基因组/转录组/蛋白 FASTA）")
    pr.add_argument("-m", "--mode", default="genome", help="分析模式：genome|transcriptome|proteins")
    pr.add_argument("-l", "--lineage", help="谱系数据集名或路径（如 basidiomycota_odb10）")
    pr.add_argument("-o", "--out-name", dest="out_name", help="输出目录名（默认 run_<input>）")
    pr.add_argument("--out-path", dest="out_path", help="输出根目录")
    pr.add_argument("--offline", action="store_true", help="离线模式（仅用本地数据库）")
    pr.add_argument("--auto-lineage", dest="auto_lineage", action="store_true",
                    help="自动选择最优谱系数据集")
    pr.add_argument("-f", "--force", action="store_true", help="覆盖已存在的输出目录")
    pr.add_argument("--extra-args", help="透传给 busco 的额外参数")
    _add_runtime_opts(pr)

    # list_datasets
    sub.add_parser("list_datasets", help=SUBCOMMANDS["list_datasets"])

    # config
    pc = sub.add_parser("config", help=SUBCOMMANDS["config"])
    pc.add_argument("config_in", nargs="?", help="输入 config.ini（默认 config/config.ini）")
    pc.add_argument("config_out", nargs="?", help="输出 config.ini")
    _add_runtime_opts(pc)

    # plot
    pp = sub.add_parser("plot", help=SUBCOMMANDS["plot"])
    pp.add_argument("-wd", "--plot-dir", dest="plot_dir", help="结果目录（含 short_summary*.txt）")
    pp.add_argument("-rt", "--plot-type", dest="plot_type", help="类型：specific|generic")
    _add_runtime_opts(pp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = BuscoSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BuscoSkill()
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
