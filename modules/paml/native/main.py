#!/usr/bin/env python3
"""paml（PAML v4.9i）native 标准入口驱动。

PAML 是分子进化分析程序套件，每个程序读取一个控制文件（*.ctl）：
    baseml baseml.ctl      # 核苷酸枝长/异常基因检测（14.md「六」）
    basemlg basemlg.ctl    # 连续伽马模型枝长
    codeml codeml.ctl      # 正选择（YN00/branch/branch-site；14.md「九」）
    yn00 yn00.ctl          # Nei-Gojobori dn/ds
    mcmctree mcmctree.ctl  # 贝叶斯分子钟/分歧时间（14.md「七」）
    evolver evolver.ctl    # 序列模拟
    infinitesites         # 无穷位点模拟（mcmctree -D INFINITESITES）
    chi2                  # 卡方临界值
    pamp pamp.ctl         # 祖先序列重建

两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py baseml baseml.ctl --threads 4 --tmpdir /tmp
   python main.py codeml codeml.ctl
   python main.py mcmctree mcmctree.ctl
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：<subcommand> <ctl>（ctl 省略时使用 PAML 默认名 <subcommand>.ctl）——
与直接在 PAML 程序所在目录敲 `<program>` 的默认行为一致。
各子命令接受 --threads / --tmpdir（PAML 各程序单线程，线程仅经 OMP_NUM_THREADS 透传）。
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
    "baseml": "baseml：核苷酸序列最大似然枝长/异常基因检测（<ctl>，默认 baseml.ctl）",
    "basemlg": "basemlg：连续伽马模型下的枝长估计（<ctl>，默认 basemlg.ctl）",
    "chi2": "chi2：卡方临界值计算（<file>，默认 chi2.ctl）",
    "codeml": "codeml：正选择分析（YN00/branch/branch-site）（<ctl>，默认 codeml.ctl）",
    "evolver": "evolver：序列/树模拟（<ctl>，默认 evolver.ctl）",
    "infinitesites": "infinitesites：无穷位点模拟（mcmctree -D INFINITESITES，默认 infinitesites.ctl）",
    "mcmctree": "mcmctree：贝叶斯分子钟/分歧时间估计（<ctl>，默认 mcmctree.ctl）",
    "pamp": "pamp：祖先序列重建（<ctl>，默认 pamp.ctl）",
    "yn00": "yn00：Nei-Gojobori 法 dn/ds 计算（<ctl>，默认 yn00.ctl）",
}


class PamlSkill(base.SkillBase):
    software = "paml"
    binary = "codeml"

    def _resolve_program(self, name: str) -> str:
        """按子命令名解析对应的 PAML 程序二进制（惰性解析，测试可 monkeypatch）。"""
        path = shutil.which(name)
        if not path:
            raise RuntimeError(
                f"未找到 PAML 程序 '{name}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda paml 提供 baseml/basemlg/chi2/codeml/evolver/infinitesites/"
                "mcmctree/pamp/yn00 全套程序）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与控制文件构建 PAML 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        # 线程提示：PAML 各程序单线程，不强加线程参数；经 OMP_NUM_THREADS 透传（对 OpenMP 构建生效）。
        threads = self._effective_threads(subcommand, kw.get("threads"))
        self.env_vars["OMP_NUM_THREADS"] = str(threads)

        program = self._resolve_program(subcommand)
        ctl = kw.get("ctl") or f"{subcommand}.ctl"
        cmd: list[str] = [program, str(ctl)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程 / 临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（经 OMP_NUM_THREADS 透传）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="paml-skill",
        description="paml（PAML v4.9i）native 技能驱动（<程序> <控制文件>；自动注入 TMPDIR）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    for name in SUBCOMMANDS:
        ps = sub.add_parser(name, help=SUBCOMMANDS[name])
        ps.add_argument("ctl", nargs="?", help=f"控制文件（默认 {name}.ctl）")
        ps.add_argument("--extra-args", dest="extra_args",
                        help="透传给该 PAML 程序的额外参数（高级用法，慎用）")
        _add_runtime_opts(ps)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = PamlSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = PamlSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

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
