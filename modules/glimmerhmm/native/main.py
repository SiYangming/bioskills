#!/usr/bin/env python3
"""glimmerhmm（GlimmerHMM）native 标准入口驱动（真核基因预测）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict genome.fasta -g -o out.gff
   python main.py predict genome.fasta --species rice -g -o out.gff
   python main.py predict genome.fasta -d /path/to/trained_dir -g -o out.gff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入临时目录（--tmpdir，同时设 TMPDIR）；glimmerhmm 为**单线程**程序，
不提供并行参数——--threads 仅作协议位接受、不注入命令行。

CLI 事实（glimmerhmm 3.0.4 二进制，2026-09 在 osx-arm64 包内实机核实 `-h` 输出）：
  USAGE: glimmerhmm <genome1-file> <training-dir-for-genome1> [options]
    -p file  读取蛋白域搜索结果（若有）
    -d dir   指定训练目录（兼容旧版）
    -o file  结果写入 file（配 -n 时写 file.1、file.2…）
    -n n     输出 top n 个最佳预测
    -g       输出 GFF 格式
    -v       不使用 svm 剪接位点预测
    -f       不做部分（partial）基因预测
    -h       显示选项
  注：上游用户手册（man.shtml）的 "No options" 段落已过期；以上为 3.0.4 二进制实际选项。
  -f 是「禁部分基因预测」布尔开关，**不是**输出 CDS FASTA（glimmerhmm 无 FASTA 输出选项）。

训练模型：包内 $PREFIX/share/glimmerhmm/trained_dir/<species>（随包物种 arabidopsis /
rice / human / zebrafish / Celegans，**无真菌模型**）；antiSMASH 真菌模式自带训练集，用
--training-dir 传入。缺省由驱动从 $CONDA_PREFIX / 二进制所在前缀自动解析。

注意：glimmerhmm **每次只处理输入 FASTA 的首条记录**（实测多记录输入仅输出第一条；
多 contig 基因组请逐条拆分后分别预测，或用随包 bin/glimmhmm.pl 包装）。
"""
from __future__ import annotations

import argparse
import json
import os
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
    "predict": "glimmerhmm：真核基因组 FASTA → 基因预测（-g 输出 GFF3，-o 写文件，"
               "训练目录 -d/--species 指定）",
}

# 包内随附训练模型（$PREFIX/share/glimmerhmm/trained_dir/<species>）
TRAINED_SUBDIR = ("share", "glimmerhmm", "trained_dir")
PACKAGE_SPECIES = ("arabidopsis", "rice", "human", "zebrafish", "Celegans")
DEFAULT_SPECIES = "arabidopsis"


class GlimmerhmmSkill(base.SkillBase):
    software = "glimmerhmm"
    binary = "glimmerhmm"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/glimmerhmm/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    # -- 训练目录解析 ------------------------------------------------------- #
    def _default_training_base(self) -> Path | None:
        """从 conda 前缀 / 二进制所在前缀定位包内 trained_dir 根目录。"""
        candidates: list[Path] = []
        for env in ("CONDA_PREFIX", "PREFIX"):
            if os.environ.get(env):
                candidates.append(Path(os.environ[env]))
        candidates.append(Path(sys.prefix))
        exe = shutil.which(self.binary)
        if exe:
            # <prefix>/bin/glimmerhmm -> <prefix>
            candidates.append(Path(exe).resolve().parent.parent)
        for root in candidates:
            d = root.joinpath(*TRAINED_SUBDIR)
            if d.is_dir():
                return d
        return None

    def _resolve_training_dir(self, kw: dict) -> str:
        """确定训练目录：显式 --training-dir 优先，否则从包内前缀按 --species 解析。"""
        explicit = kw.get("training_dir")
        if explicit:
            d = Path(explicit)
            if not (d / "config.file").exists():
                raise RuntimeError(
                    f"--training-dir '{explicit}' 不是有效训练目录（缺 config.file；"
                    "glimmerhmm 训练目录须含 config.file 等模型文件）"
                )
            return str(d)

        species = str(kw.get("species") or DEFAULT_SPECIES)
        base_dir = self._default_training_base()
        if base_dir is None:
            raise RuntimeError(
                "未找到包内训练目录（<prefix>/share/glimmerhmm/trained_dir）；"
                "请先安装 glimmerhmm（conda/官方容器），或用 --training-dir 指定训练目录"
                "（如 antiSMASH 真菌模式自带的 GlimmerHMM 训练集）"
            )
        target = base_dir / species
        if (target / "config.file").exists():
            return str(target)
        available = sorted(p.name for p in base_dir.iterdir()
                           if (p / "config.file").exists())
        raise RuntimeError(
            f"包内训练目录无 '{species}' 模型（可用：{', '.join(available) or '无'}）；"
            "请改用 --species 指定随包物种，或用 --training-dir 指定自定义训练目录"
        )

    # -- 命令构建 ----------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 glimmerhmm 命令行（不执行）。"""
        if subcommand != "predict":
            raise RuntimeError(f"未知子命令: {subcommand}")

        genome = kw.get("genome_fasta")
        if not genome:
            raise RuntimeError("predict 需要 genome_fasta（真核基因组 FASTA，位置参数）")
        genome = str(genome)
        if not Path(genome).is_file():
            raise RuntimeError(f"genome_fasta 不存在: {genome}")

        cmd: list[str] = [self._resolve_binary(), genome]
        cmd += ["-d", self._resolve_training_dir(kw)]

        if kw.get("gff"):
            cmd.append("-g")
        if kw.get("no_partial"):
            cmd.append("-f")
        output = kw.get("output")
        if output:
            cmd += ["-o", str(output)]

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="glimmerhmm-skill",
        description="glimmerhmm native 技能驱动（自动 TMPDIR；真核基因预测，单线程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # predict: glimmerhmm <genome.fasta> -d <training_dir> [-g] [-f] [-o OUT]
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("genome_fasta", help="真核基因组 FASTA（单/多 contig；glimmerhmm 位置参数）")
    pp.add_argument(
        "-d", "--training-dir", dest="training_dir",
        help="训练目录（含 config.file 的物种模型目录）；缺省由驱动从包前缀 "
             "$CONDA_PREFIX/share/glimmerhmm/trained_dir/<species> 自动解析",
    )
    pp.add_argument(
        "--species", choices=PACKAGE_SPECIES, default=DEFAULT_SPECIES,
        help=f"未给 --training-dir 时选用包内物种模型（默认 {DEFAULT_SPECIES}；"
             f"随包物种：{'/'.join(PACKAGE_SPECIES)}）",
    )
    pp.add_argument("-g", "--gff", action="store_true",
                    help="输出 GFF3 格式（缺省为 GlimmerHMM 原生表格结果）")
    pp.add_argument("-f", "--no-partial", dest="no_partial", action="store_true",
                    help="不做部分（partial）基因预测（glimmerhmm 原生 -f 语义）")
    pp.add_argument("-o", "--output", help="预测结果输出文件（缺省 stdout）")
    pp.add_argument("--extra-args", dest="extra_args",
                    help="透传给 glimmerhmm 的额外参数（如 -n 3 / -p domains.txt / -v，高级用法，慎用）")
    _add_runtime_opts(pp)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程协议位/临时目录）。"""
    p.add_argument("--threads", type=int,
                   help="线程协议位（glimmerhmm 单线程，接受但不注入命令行）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（同时注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GlimmerhmmSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GlimmerhmmSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

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
