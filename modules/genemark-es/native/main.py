#!/usr/bin/env python3
"""genemark-es native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py es genome.fasta --fungus --threads 8
   python main.py et genome.fasta --introns genemarkET.intron.gff --fungus --et-score 10 --threads 8
   python main.py convert_hints genome.fasta hints.gff -o genemarkET.intron.gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（GeneMark-ES/ET 4.72_lic，gmes_petap.pl）：
  es              gmes_petap.pl --sequence <genome.fasta> --ES  [--fungus] [--soft_mask 1] --cores N
  et              gmes_petap.pl --sequence <genome.fasta> --ET <introns.gff> [--fungus] [--et_score N] --cores N
  convert_hints   hints2genemarkETintron.pl <genome.fasta> <hints.gff>     # GFF 写 stdout
脚本按 GENEMARK_PATH / ~/software/gmes_linux_64*/ / PATH 惰性解析（测试时 monkeypatch）。
运行需许可密钥 ~/.gm_key（官网申请；官方许可禁止再分发）。
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
    "es": "gmes_petap.pl --sequence <genome.fasta> --ES [--fungus] --cores N（无监督从头预测）",
    "et": "gmes_petap.pl --sequence <genome.fasta> --ET <introns.gff> [--fungus] --cores N（结合 RNA-seq hints）",
    "convert_hints": "hints2genemarkETintron.pl <genome.fasta> <hints.gff>（AUGUSTUS hints → GeneMark-ET 内含子，写 stdout）",
}

# 子命令 -> 上游脚本名
SCRIPTS = {
    "es": "gmes_petap.pl",
    "et": "gmes_petap.pl",
    "convert_hints": "hints2genemarkETintron.pl",
}


class GeneMarkESSkill(base.SkillBase):
    software = "genemark-es"
    binary = "gmes_petap.pl"

    def _resolve_script(self, name: str) -> str:
        """惰性解析 GeneMark 脚本路径（GENEMARK_PATH / ~/software/gmes_linux_64*/ / PATH）。"""
        home = os.environ.get("GENEMARK_PATH") or os.environ.get("GENEMARK_DIR")
        if home:
            for cand in (Path(home) / name, Path(home) / "bin" / name):
                if cand.is_file():
                    return str(cand)
        for cand in (sorted(Path.home().glob(f"software/gmes_linux_64*/{name}"))
                     + sorted(Path.home().glob(f"software/gmes_linux_64*/bin/{name}"))):
            if cand.is_file():
                return str(cand)
        found = base.which(name)
        if found:
            return found
        raise RuntimeError(
            f"未找到 GeneMark 脚本 '{name}'：请先通过 native/install.sh（或 Dockerfile/Apptainer.def）安装，"
            f"或设置 GENEMARK_PATH 指向 gmes_linux_64* 安装目录。注意运行需 ~/.gm_key（官网申请）。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 gmes_petap.pl / hints2genemarkETintron.pl 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        cmd: list[str] = [self._resolve_script(SCRIPTS[subcommand])]

        if subcommand in ("es", "et"):
            genome = kw.get("genome") or kw.get("input")
            if not genome:
                raise ValueError(f"{subcommand} 缺少必填参数 genome（基因组 FASTA）")
            cmd += ["--sequence", str(genome)]
            if subcommand == "es":
                cmd.append("--ES")
            else:
                introns = kw.get("introns")
                if not introns:
                    raise ValueError("et 缺少必填参数 introns（GeneMark-ET 内含子 hints GFF）")
                cmd += ["--ET", str(introns)]
                if kw.get("et_score") is not None:
                    cmd += ["--et_score", str(kw["et_score"])]
            if kw.get("fungus"):
                cmd.append("--fungus")
            if kw.get("soft_mask") is not None:
                cmd += ["--soft_mask", str(kw["soft_mask"])]
            cmd += ["--cores", str(self._effective_threads(subcommand, kw.get("threads")))]

        elif subcommand == "convert_hints":
            genome = kw.get("genome") or kw.get("input")
            hints = kw.get("hints")
            if not genome or not hints:
                raise ValueError("convert_hints 缺少必填参数 genome（基因组 FASTA）或 hints（hints GFF）")
            cmd += [str(genome), str(hints)]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入 --cores）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="genemark-es-skill",
        description="genemark-es native 技能驱动（gmes_petap.pl；自动注入 --cores）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # es
    pe = sub.add_parser("es", help=SUBCOMMANDS["es"])
    pe.add_argument("genome", nargs="?", help="基因组序列 FASTA（别名 --genome）")
    pe.add_argument("--genome", help="基因组序列 FASTA 的别名")
    pe.add_argument("--fungus", action="store_true", help="真菌模式")
    pe.add_argument("--soft-mask", dest="soft_mask", type=int, help="软屏蔽重复序列开关（1=开启）")
    pe.add_argument("--extra-args", help="透传给 gmes_petap.pl 的额外参数")
    _add_runtime_opts(pe)

    # et
    pet = sub.add_parser("et", help=SUBCOMMANDS["et"])
    pet.add_argument("genome", nargs="?", help="基因组序列 FASTA（别名 --genome）")
    pet.add_argument("--genome", help="基因组序列 FASTA 的别名")
    pet.add_argument("--introns", help="GeneMark-ET 内含子 hints GFF")
    pet.add_argument("--et-score", dest="et_score", type=int, help="ET 模式得分阈值（如 10）")
    pet.add_argument("--fungus", action="store_true", help="真菌模式")
    pet.add_argument("--soft-mask", dest="soft_mask", type=int, help="软屏蔽重复序列开关（1=开启）")
    pet.add_argument("--extra-args", help="透传给 gmes_petap.pl 的额外参数")
    _add_runtime_opts(pet)

    # convert_hints
    ph = sub.add_parser("convert_hints", help=SUBCOMMANDS["convert_hints"])
    ph.add_argument("genome", nargs="?", help="基因组序列 FASTA（别名 --genome）")
    ph.add_argument("--genome", help="基因组序列 FASTA 的别名")
    ph.add_argument("--hints", help="AUGUSTUS 风格 hints GFF")
    ph.add_argument("-o", "--output", help="输出 GeneMark-ET 内含子 GFF（默认写 stdout）")
    ph.add_argument("--extra-args", help="透传给 hints2genemarkETintron.pl 的额外参数")
    _add_runtime_opts(ph)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = GeneMarkESSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GeneMarkESSkill()
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

    # convert_hints 的 stdout 落到 output 文件
    if ns.subcommand == "convert_hints" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
