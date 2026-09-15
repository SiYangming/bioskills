#!/usr/bin/env python3
"""augustus native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict genome.fasta --species=malassezia_sympodialis --hintsfile=hints.gff -o aug.gff
   python main.py etraining genes.gb --species=malassezia_sympodialis --crf 1
   python main.py optimize genes.gb.train --species=malassezia_sympodialis --rounds 5 --kfold 8 --threads 8
   python main.py new_species --species=malassezia_sympodialis
   python main.py gff2gb ati.filter2.gff3 genome.fasta --flank 100 -o genes.raw.gb
   python main.py bam2hints rnaseq.sort.bam --intronsonly -o hints.gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（AUGUSTUS 3.4.0）：
  predict       augustus --species=<s> [--hintsfile=<f>] [--CRF=1] <genome.fasta>     # GFF 写 stdout
  etraining     etraining --species=<s> [--CRF=1] <genes.gb>
  optimize      optimize_augustus.pl --species=<s> --rounds=N --cpus=N --kfold=N <genes.gb.train>
  new_species   new_species.pl --species=<s>
  gff2gb        gff2gbSmallDNA.pl <gff> <genome.fasta> <flank> <out.gb>
  bam2hints     bam2hints [--intronsonly] --in=<bam> --out=<hints.gff>
二进制/脚本按 AUGUSTUS_BIN_PATH / AUGUSTUS_SCRIPTS_PATH / ~/software/augustus*/ / PATH 惰性解析（测试时 monkeypatch）。
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
    "predict": "augustus：用训练好的物种参数预测基因结构（--species/--hintsfile，GFF 写 stdout）",
    "etraining": "etraining：用 GenBank 训练集训练物种参数（--species/--CRF）",
    "optimize": "optimize_augustus.pl：循环训练优化 HMM 参数（--rounds/--cpus/--kfold）",
    "new_species": "new_species.pl：为新物种创建参数目录（--species）",
    "gff2gb": "gff2gbSmallDNA.pl：GFF3 → GenBank 训练集（gff genome flank out.gb）",
    "bam2hints": "bam2hints：RNA-seq 比对 BAM → hints GFF（--in/--out，--intronsonly）",
}

# 子命令 -> (上游可执行名, 类型 bin|scripts)
TOOLS = {
    "predict": ("augustus", "bin"),
    "etraining": ("etraining", "bin"),
    "optimize": ("optimize_augustus.pl", "scripts"),
    "new_species": ("new_species.pl", "scripts"),
    "gff2gb": ("gff2gbSmallDNA.pl", "scripts"),
    "bam2hints": ("bam2hints", "bin"),
}


class AugustusSkill(base.SkillBase):
    software = "augustus"
    binary = "augustus"

    def _resolve_tool(self, name: str, kind: str) -> str:
        """惰性解析 AUGUSTUS 二进制/脚本路径（AUGUSTUS_*_PATH / ~/software/augustus*/ / PATH）。"""
        env_key = "AUGUSTUS_BIN_PATH" if kind == "bin" else "AUGUSTUS_SCRIPTS_PATH"
        base_dir = os.environ.get(env_key)
        if base_dir and (Path(base_dir) / name).is_file():
            return str(Path(base_dir) / name)
        for cand in sorted(Path.home().glob(f"software/augustus*/{kind}/{name}")):
            if cand.is_file():
                return str(cand)
        found = base.which(name)
        if found:
            return found
        raise RuntimeError(
            f"未找到 AUGUSTUS {'脚本' if kind == 'scripts' else '二进制'} '{name}'：请先通过 native/install.sh"
            f"（或 Docker/Apptainer）安装，或设置 {env_key} 指向 augustus 的 {kind} 目录。"
        )

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 augustus/etraining/脚本命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        name, kind = TOOLS[subcommand]
        cmd: list[str] = [self._resolve_tool(name, kind)]

        if subcommand == "predict":
            genome = kw.get("genome") or kw.get("input")
            if not genome:
                raise ValueError("predict 缺少必填参数 genome（基因组 FASTA）")
            if not kw.get("species"):
                raise ValueError("predict 缺少必填参数 species（物种参数名）")
            cmd.append(f"--species={kw['species']}")
            if kw.get("hintsfile"):
                cmd.append(f"--hintsfile={kw['hintsfile']}")
            if kw.get("allow_hinted_splicesites"):
                cmd.append(f"--allow_hinted_splicesites={kw['allow_hinted_splicesites']}")
            if kw.get("alternatives_from_evidence"):
                cmd.append("--alternatives-from-evidence=true")
            if kw.get("crf"):
                cmd.append(f"--CRF={kw['crf']}")
            cmd.append(str(genome))

        elif subcommand == "etraining":
            genes = kw.get("genes_gb") or kw.get("input")
            if not genes:
                raise ValueError("etraining 缺少必填参数 genes_gb（GenBank 训练集）")
            if not kw.get("species"):
                raise ValueError("etraining 缺少必填参数 species（物种参数名）")
            cmd.append(f"--species={kw['species']}")
            if kw.get("crf"):
                cmd.append(f"--CRF={kw['crf']}")
            if kw.get("stop_codon_excluded") is False:
                cmd.append("--stopCodonExcludedFromCDS=false")
            cmd.append(str(genes))

        elif subcommand == "optimize":
            genes = kw.get("genes_gb") or kw.get("input")
            if not genes:
                raise ValueError("optimize 缺少必填参数 genes_gb（GenBank 训练集）")
            if not kw.get("species"):
                raise ValueError("optimize 缺少必填参数 species（物种参数名）")
            cmd.append(f"--species={kw['species']}")
            if kw.get("rounds") is not None:
                cmd += ["--rounds", str(kw["rounds"])]
            cmd += ["--cpus", str(self._effective_threads(subcommand, kw.get("threads")))]
            if kw.get("kfold") is not None:
                cmd += ["--kfold", str(kw["kfold"])]
            if kw.get("onlytrain"):
                cmd += ["--onlytrain", str(kw["onlytrain"])]
            cmd.append(str(genes))

        elif subcommand == "new_species":
            if not kw.get("species"):
                raise ValueError("new_species 缺少必填参数 species（物种参数名）")
            cmd.append(f"--species={kw['species']}")

        elif subcommand == "gff2gb":
            gff = kw.get("annotation") or kw.get("input")
            genome = kw.get("genome")
            if not gff or not genome:
                raise ValueError("gff2gb 缺少必填参数 annotation（GFF3）或 genome（基因组 FASTA）")
            cmd += [str(gff), str(genome), str(kw.get("flank", 100))]
            if kw.get("output"):
                cmd.append(str(kw["output"]))

        elif subcommand == "bam2hints":
            bam = kw.get("bam") or kw.get("input")
            if not bam:
                raise ValueError("bam2hints 缺少必填参数 bam（RNA-seq 比对 BAM）")
            if kw.get("intronsonly", True):
                cmd.append("--intronsonly")
            cmd.append(f"--in={bam}")
            if kw.get("output"):
                cmd.append(f"--out={kw['output']}")

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（optimize 注入 --cpus）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="augustus-skill",
        description="augustus native 技能驱动（predict/etraining/optimize/... 自动注入线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("genome", nargs="?", help="基因组序列 FASTA")
    pp.add_argument("--input", help="基因组 FASTA 的别名")
    pp.add_argument("--species", help="物种参数名（如 malassezia_sympodialis）")
    pp.add_argument("--hintsfile", help="RNA-seq hints GFF")
    pp.add_argument("--allow-hinted-splicesites", dest="allow_hinted_splicesites",
                    help="允许的非标准剪接位点（如 atac）")
    pp.add_argument("--alternatives-from-evidence", dest="alternatives_from_evidence",
                    action="store_true", help="从证据中提取可变剪接异构体")
    pp.add_argument("--crf", type=int, help="启用 CRF（--CRF=1）")
    pp.add_argument("-o", "--output", help="输出 GFF 路径（默认写 stdout）")
    pp.add_argument("--extra-args", help="透传给 augustus 的额外参数")
    _add_runtime_opts(pp)

    # etraining
    pe = sub.add_parser("etraining", help=SUBCOMMANDS["etraining"])
    pe.add_argument("genes_gb", nargs="?", help="GenBank 训练集（genes.gb）")
    pe.add_argument("--input", help="GenBank 训练集的别名")
    pe.add_argument("--species", help="物种参数名")
    pe.add_argument("--crf", type=int, help="启用 CRF（--CRF=1）")
    pe.add_argument("--include-stop-codon", dest="stop_codon_excluded", action="store_false",
                    help="设置 --stopCodonExcludedFromCDS=false")
    pe.add_argument("--extra-args", help="透传给 etraining 的额外参数")
    _add_runtime_opts(pe)

    # optimize
    po = sub.add_parser("optimize", help=SUBCOMMANDS["optimize"])
    po.add_argument("genes_gb", nargs="?", help="GenBank 训练集（genes.gb.train）")
    po.add_argument("--input", help="GenBank 训练集的别名")
    po.add_argument("--species", help="物种参数名")
    po.add_argument("--rounds", type=int, help="优化轮数（如 5）")
    po.add_argument("--kfold", type=int, help="交叉验证折数（如 8）")
    po.add_argument("--onlytrain", help="仅用于训练的基因集文件")
    po.add_argument("--extra-args", help="透传给 optimize_augustus.pl 的额外参数")
    _add_runtime_opts(po)

    # new_species
    pn = sub.add_parser("new_species", help=SUBCOMMANDS["new_species"])
    pn.add_argument("--species", help="物种参数名")
    pn.add_argument("--extra-args", help="透传给 new_species.pl 的额外参数")
    _add_runtime_opts(pn)

    # gff2gb
    pg = sub.add_parser("gff2gb", help=SUBCOMMANDS["gff2gb"])
    pg.add_argument("annotation", nargs="?", help="输入 GFF3 注释")
    pg.add_argument("--input", help="输入 GFF3 的别名")
    pg.add_argument("--genome", help="基因组序列 FASTA")
    pg.add_argument("--flank", type=int, default=100, help="基因前后 flank 长度（bp，默认 100）")
    pg.add_argument("-o", "--output", help="输出 GenBank 路径（genes.raw.gb）")
    pg.add_argument("--extra-args", help="透传给 gff2gbSmallDNA.pl 的额外参数")
    _add_runtime_opts(pg)

    # bam2hints
    pb = sub.add_parser("bam2hints", help=SUBCOMMANDS["bam2hints"])
    pb.add_argument("bam", nargs="?", help="RNA-seq 比对 BAM")
    pb.add_argument("--input", help="BAM 的别名")
    pb.add_argument("-o", "--output", help="输出 hints GFF 路径")
    pb.add_argument("--no-intronsonly", dest="intronsonly", action="store_false",
                    help="关闭 --intronsonly")
    pb.add_argument("--extra-args", help="透传给 bam2hints 的额外参数")
    _add_runtime_opts(pb)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = AugustusSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AugustusSkill()
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

    # predict 的 stdout 落到 output 文件（augustus 写 stdout）
    if ns.subcommand == "predict" and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
