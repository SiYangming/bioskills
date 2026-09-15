#!/usr/bin/env python3
"""SOAPdenovo2 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R
   python main.py pregraph -s config.txt -o out_K51/E_coli -K 51 -R
   python main.py contig -g out_K51/E_coli -R
   python main.py map -s config.txt -g out_K51/E_coli
   python main.py scaff -g out_K51/E_coli -F
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（文档 04.md 第 825-831 行）：
  all       SOAPdenovo-63mer all -s <config> -o <prefix> -K <k> -p N [-R] [-d] [-D]
  pregraph  SOAPdenovo-63mer pregraph -s <config> -o <prefix> -K <k> -p N [-R]
  contig    SOAPdenovo-63mer contig -g <prefix> [-R]
  map       SOAPdenovo-63mer map -s <config> -g <prefix>
  scaff     SOAPdenovo-63mer scaff -g <prefix> [-F]
--mer 127 时程序改为 SOAPdenovo-127mer（k-mer 上限 127）。
线程优先级：用户 --threads > optimization.per_subcommand_threads > default_cpus（仅 all/pregraph 注入 -p）。
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
    "all": "一步式组装 pregraph→contig→map→scaff（SOAPdenovo-63mer/127mer all，需 -s config -o prefix）",
    "pregraph": "构建 de Bruijn 图（pregraph -s config -o prefix -K k）",
    "contig": "由图构建 contig（contig -g <prefix>）",
    "map": "将 reads 比对回 contig（map -s config -g <prefix>）",
    "scaff": "利用配对信息构建 scaffold（scaff -g <prefix> [-F]）",
}

# 会注入 -p 线程的子命令（其余子命令官方无 -p 选项）
THREAD_SUBCOMMANDS = {"all", "pregraph"}


class Soapdenovo2Skill(base.SkillBase):
    software = "soapdenovo2"
    binary = "SOAPdenovo-63mer"

    # -- 二进制解析 --------------------------------------------------------- #
    def _mer_binary(self, mer: int | None) -> str:
        """按 --mer 选择 SOAPdenovo-63mer / SOAPdenovo-127mer（默认 63）。"""
        return "SOAPdenovo-127mer" if int(mer or 63) == 127 else "SOAPdenovo-63mer"

    def _resolve_binary(self, name: str | None = None) -> str:
        """惰性解析二进制（可被测试 monkeypatch）；name 缺省时用 self.binary。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 SOAPdenovo 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(self._mer_binary(kw.get("mer")))
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd: list[str] = [binary, subcommand]

        if subcommand in ("all", "pregraph"):
            config = kw.get("config") or kw.get("input")
            if not config:
                raise ValueError(f"{subcommand} 缺少必填参数 config（-s config.txt）")
            out = kw.get("output")
            if not out:
                raise ValueError(f"{subcommand} 缺少必填参数 output（-o 输出前缀）")
            cmd += ["-s", str(config), "-o", str(out)]
            if kw.get("kmer") is not None:
                cmd += ["-K", str(kw["kmer"])]
            cmd += ["-p", str(threads)]
            if kw.get("resolve_repeats"):
                cmd.append("-R")
            if kw.get("kmer_freq_cutoff") is not None:
                cmd += ["-d", str(kw["kmer_freq_cutoff"])]
            if kw.get("edge_cov_cutoff") is not None:
                cmd += ["-D", str(kw["edge_cov_cutoff"])]

        elif subcommand == "contig":
            g = kw.get("graph_prefix") or kw.get("output")
            if not g:
                raise ValueError("contig 缺少必填参数 graph_prefix（-g 图前缀）")
            cmd += ["-g", str(g)]
            if kw.get("resolve_repeats"):
                cmd.append("-R")

        elif subcommand == "map":
            g = kw.get("graph_prefix") or kw.get("output")
            if not g:
                raise ValueError("map 缺少必填参数 graph_prefix（-g 图前缀）")
            config = kw.get("config")
            if config:
                cmd += ["-s", str(config)]
            cmd += ["-g", str(g)]

        elif subcommand == "scaff":
            g = kw.get("graph_prefix") or kw.get("output")
            if not g:
                raise ValueError("scaff 缺少必填参数 graph_prefix（-g 图前缀）")
            cmd += ["-g", str(g)]
            if kw.get("fill_gaps"):
                cmd.append("-F")

        # 高级透传（慎用）
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


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--mer", type=int, choices=(63, 127), default=63,
                   help="选择 SOAPdenovo-63mer（63，默认）或 SOAPdenovo-127mer（127）")
    p.add_argument("--extra-args", help="透传给 SOAPdenovo 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="soapdenovo2-skill",
        description="SOAPdenovo2 native 技能驱动（自动线程/临时目录优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # all
    pa = sub.add_parser("all", help=SUBCOMMANDS["all"])
    pa.add_argument("config", nargs="?", help="config.txt 配置文件（别名 --config）")
    pa.add_argument("--config", dest="config_alias", help="config.txt 别名")
    pa.add_argument("-o", "--output", help="输出图/结果前缀")
    pa.add_argument("-K", "--kmer", type=int, default=51, help="k-mer 长度（奇数，默认 51）")
    pa.add_argument("-R", "--resolve-repeats", action="store_true", help="用 reads 解决重复")
    pa.add_argument("-d", "--kmer-freq-cutoff", type=int, help="k-mer 频率过滤阈值")
    pa.add_argument("-D", "--edge-cov-cutoff", type=int, help="边覆盖度过滤阈值")
    _add_common(pa)
    _add_runtime_opts(pa)

    # pregraph
    pp = sub.add_parser("pregraph", help=SUBCOMMANDS["pregraph"])
    pp.add_argument("config", nargs="?", help="config.txt 配置文件")
    pp.add_argument("--config", dest="config_alias", help="config.txt 别名")
    pp.add_argument("-o", "--output", help="输出图前缀")
    pp.add_argument("-K", "--kmer", type=int, default=51, help="k-mer 长度（默认 51）")
    pp.add_argument("-R", "--resolve-repeats", action="store_true", help="用 reads 解决重复")
    _add_common(pp)
    _add_runtime_opts(pp)

    # contig
    pc = sub.add_parser("contig", help=SUBCOMMANDS["contig"])
    pc.add_argument("-g", "--graph-prefix", help="上一步图前缀")
    pc.add_argument("-R", "--resolve-repeats", action="store_true", help="用 reads 解决重复")
    _add_common(pc)
    _add_runtime_opts(pc)

    # map
    pm = sub.add_parser("map", help=SUBCOMMANDS["map"])
    pm.add_argument("-g", "--graph-prefix", help="图前缀")
    pm.add_argument("-s", "--config", help="config.txt 配置文件")
    _add_common(pm)
    _add_runtime_opts(pm)

    # scaff
    ps = sub.add_parser("scaff", help=SUBCOMMANDS["scaff"])
    ps.add_argument("-g", "--graph-prefix", help="图前缀")
    ps.add_argument("-F", "--fill-gaps", action="store_true", help="填补 gap")
    _add_common(ps)
    _add_runtime_opts(ps)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Soapdenovo2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Soapdenovo2Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    # positional config 与 --config 别名合并为 config
    if "config_alias" in kw:
        kw.setdefault("config", kw.pop("config_alias"))
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
