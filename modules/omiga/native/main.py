#!/usr/bin/env python3
"""omiga native 标准入口驱动（继承 base.SkillBase）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run --mode cis --genotype geno --phenotype pheno.txt --prefix out --output-dir res --threads 8
   python main.py init                  # 等价 omiga --init（首跑前初始化，产出 OK 自检文件）
   python main.py update                # 等价 omiga --update（1.8.14+ 联网自升级）
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py <sub> ... --dry-run   # 只打印构建出的命令，不执行

子命令与参数对齐上游 OmiGA 单一大命令形态（SCAU-AnimalGenetics/OmiGA v1.8.17，官网
https://omiga.bio/ Installation.md / 2026-09-07 核实）：
  run    omiga --mode <MODE> --threads N --genotype <plink前缀> --phenotype <file>
         [--covariates <file>] --prefix <p> --output-dir <dir>
         （--mode 含 cis / cis_independent / cis_interaction / cis_mt / trans / GWAS(gwas) /
          her_est / enrich / plot 等，以 omiga --help 实际清单为准；本驱动不臆造模式内具体 flag，
          白名单外参数经 --extra-args 原样透传）
  init   omiga --init   （首跑前初始化）
  update omiga --update （联网自升级；官方亦记载 `omiga update` 形态，本驱动默认用 --update）
说明：omiga 本体为官方 Linux x86_64 预编译二进制（自带运行时），无子命令体系 —— 本驱动的
run/init/update 是技能层子命令（对齐官方顶层 flag），与上游多子命令软件（如 samtools）不同。
--threads 自动注入（缺省取 meta optimization 默认 4；用户显式 --threads 优先），对齐官方
`--mode <MODE> --threads N` 的调用形态。
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

# 子命令语义清单（用于 --list-commands 与 Schema description；对齐官方大命令顶层 flag）
SUBCOMMANDS = {
    "run": "转发 omiga --mode <MODE> 分析（cis/trans/GWAS/her_est/enrich/plot 等；--threads 自动注入）",
    "init": "首跑前初始化（等价 omiga --init；产出 OK 自检文件）",
    "update": "联网自升级（等价 omiga --update；1.8.14+ 支持，官方亦记载 `omiga update` 形态）",
}

# run 已知的 --mode 值（官方手册列出的子模式；omiga --help 实际清单为准，未知值经 --mode 原样放行）
KNOWN_MODES = (
    "cis", "cis_independent", "cis_interaction", "cis_mt", "trans",
    "GWAS", "gwas", "her_est", "enrich", "plot",
)


class OmiGASkill(base.SkillBase):
    software = "omiga"
    binary = "omiga"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        if isinstance(per, dict):
            return int(per.get(subcommand, per.get("default", self.cpus)))
        return int(self.cpus)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 omiga 命令行（代理官方单一大命令）。

        - init  → omiga --init
        - update → omiga --update
        - run    → omiga --mode <MODE> --threads N [白名单参数] [extra_args]
        """
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()

        if subcommand == "init":
            return [binary, "--init"]
        if subcommand == "update":
            return [binary, "--update"]

        # run
        mode = kw.get("mode")
        if not mode:
            raise ValueError("run 需要 --mode <MODE>（cis/cis_independent/cis_interaction/cis_mt/"
                             "trans/GWAS(gwas)/her_est/enrich/plot 等，以 omiga --help 为准）")
        threads = self._effective_threads("run", kw.get("threads"))
        cmd: list[str] = [binary, "--mode", str(mode), "--threads", str(threads)]
        # 白名单转发（仅当给出时；上游示例参数次序：--genotype --phenotype [--covariates]
        # --prefix --output-dir；不臆造模式内专属 flag）
        pairs = (
            ("genotype", "--genotype"),
            ("phenotype", "--phenotype"),
            ("covariates", "--covariates"),
            ("prefix", "--prefix"),
            ("output_dir", "--output-dir"),
        )
        for key, flag in pairs:
            val = kw.get(key)
            if val is not None and str(val) != "":
                cmd += [flag, str(val)]
        # 白名单外的上游参数（高级用法）原样透传，追加到命令末尾
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖线程数（run 经 --threads 注入；缺省取 optimization 默认）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="omiga-skill",
        description="omiga native 技能驱动（run / init / update；对齐官方单一大命令 --mode 形态）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run：转发 omiga --mode <MODE> 分析
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("--mode", dest="mode", default=None,
                    help=f"分析模式（已知: {'/'.join(KNOWN_MODES)} 等；以 omiga --help 为准）")
    pr.add_argument("--genotype", dest="genotype", default=None, help="基因型 PLINK 前缀（<前缀>.bed/.bim/.fam）")
    pr.add_argument("--phenotype", dest="phenotype", default=None, help="表型文件")
    pr.add_argument("--covariates", dest="covariates", default=None, help="协变量文件（可选）")
    pr.add_argument("--prefix", dest="prefix", default=None, help="输出结果前缀")
    pr.add_argument("--output-dir", dest="output_dir", default=None, help="输出目录")
    pr.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外的上游参数原样透传（如其它 --mode 专属参数；用引号包裹）")
    _add_runtime_opts(pr)

    # init：omiga --init
    pi = sub.add_parser("init", help=SUBCOMMANDS["init"])
    _add_runtime_opts(pi)

    # update：omiga --update
    pu = sub.add_parser("update", help=SUBCOMMANDS["update"])
    _add_runtime_opts(pu)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = OmiGASkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = OmiGASkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
        return 0

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
