#!/usr/bin/env python3
"""snap native 标准入口驱动。

SNAP（KorfLab）训练 + 预测全链路的自包含驱动，覆盖 7 个子命令：
  gene_stats     fathom <ann> <dna> -gene-stats
  validate       fathom <ann> <dna> -validate
  categorize     fathom <ann> <dna> -categorize <window>
  export         fathom <ann> <dna> -export <window> -plus
  forge          forge <export.ann> <export.dna>
  hmm_assembler  hmm-assembler.pl <name> <params>      （写 stdout -> --output）
  predict        snap <hmm> <genome>                   （写 stdout -> --output）

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py predict species.hmm genome.fasta -o snap_out.zff
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

线程说明：SNAP 的 fathom/forge/snap 均为单线程程序；各子命令仍接受 --threads/--tmpdir
以保持接口一致（--threads 不向二进制透传）。
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
    "gene_stats": "fathom -gene-stats：统计训练集基因信息",
    "validate": "fathom -validate：校验训练基因模型",
    "categorize": "fathom -categorize <window>：按类别拆分基因模型",
    "export": "fathom -export <window> -plus：导出训练数据（export.ann/export.dna）",
    "forge": "forge：由 export.ann/export.dna 构建 HMM 参数",
    "hmm_assembler": "hmm-assembler.pl：由 HMM 参数生成 species.hmm（stdout）",
    "predict": "snap：用 species.hmm 对基因组做基因预测（stdout，ZFF）",
}

# 子命令 -> 实际调用的二进制（惰性解析）
BINARIES = {
    "gene_stats": "fathom",
    "validate": "fathom",
    "categorize": "fathom",
    "export": "fathom",
    "forge": "forge",
    "hmm_assembler": "hmm-assembler.pl",
    "predict": "snap",
}

# stdout 需重定向到 --output 的子命令
STDOUT_SUBCOMMANDS = {"hmm_assembler", "predict"}


class SnapSkill(base.SkillBase):
    software = "snap"
    binary = "snap"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析所需二进制（fathom / forge / hmm-assembler.pl / snap）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 SNAP 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary(BINARIES[subcommand])
        cmd: list[str] = [binary]

        if subcommand in ("gene_stats", "validate", "categorize", "export"):
            ann = kw.get("ann") or kw.get("annotation")
            dna = kw.get("dna") or kw.get("genome")
            if not ann or not dna:
                raise ValueError(f"{subcommand} 缺少必填参数 ann/dna")
            cmd += [str(ann), str(dna)]
            if subcommand == "gene_stats":
                cmd.append("-gene-stats")
            elif subcommand == "validate":
                cmd.append("-validate")
            elif subcommand == "categorize":
                cmd += ["-categorize", str(kw.get("window", 200))]
            elif subcommand == "export":
                cmd += ["-export", str(kw.get("window", 200))]
                if kw.get("plus", True):
                    cmd.append("-plus")

        elif subcommand == "forge":
            export_ann = kw.get("export_ann") or kw.get("ann")
            export_dna = kw.get("export_dna") or kw.get("dna")
            if not export_ann or not export_dna:
                raise ValueError("forge 缺少必填参数 export_ann/export_dna")
            cmd += [str(export_ann), str(export_dna)]

        elif subcommand == "hmm_assembler":
            name = kw.get("name") or kw.get("label")
            params = kw.get("params")
            if not name or not params:
                raise ValueError("hmm_assembler 缺少必填参数 name/params")
            cmd += [str(name), str(params)]

        elif subcommand == "predict":
            hmm = kw.get("hmm") or kw.get("model")
            genome = kw.get("genome") or kw.get("input")
            if not hmm or not genome:
                raise ValueError("predict 缺少必填参数 hmm/genome")
            cmd += [str(hmm), str(genome)]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（SNAP 单线程，仅接口一致）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--extra-args", help="透传给底层程序的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="snap-skill",
        description="snap native 技能驱动（fathom/forge/hmm-assembler.pl/snap 全链路）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # fathom 系列（ann/dna 位置参数）
    for name in ("gene_stats", "validate", "categorize", "export"):
        sp = sub.add_parser(name, help=SUBCOMMANDS[name])
        sp.add_argument("ann", help="ZFF 格式基因注释（.ann）")
        sp.add_argument("dna", help="FASTA 序列（.dna）")
        if name in ("categorize", "export"):
            sp.add_argument("-w", "--window", type=int, help="窗口大小（默认 200）")
        if name == "export":
            sp.add_argument("--no-plus", dest="plus", action="store_false", help="关闭 -plus 侧翼导出")
        _add_runtime_opts(sp)

    # forge
    pf = sub.add_parser("forge", help=SUBCOMMANDS["forge"])
    pf.add_argument("ann", help="export.ann（fathom -export 产物）")
    pf.add_argument("dna", help="export.dna（fathom -export 产物）")
    _add_runtime_opts(pf)

    # hmm-assembler.pl
    ph = sub.add_parser("hmm_assembler", help=SUBCOMMANDS["hmm_assembler"])
    ph.add_argument("name", help="物种/模型名（写入 HMM 头）")
    ph.add_argument("params", help="forge 产出的 HMM 参数目录")
    ph.add_argument("-o", "--output", help="输出 species.hmm 路径（stdout 重定向）")
    _add_runtime_opts(ph)

    # snap predict
    pp = sub.add_parser("predict", help=SUBCOMMANDS["predict"])
    pp.add_argument("hmm", help="训练好的 HMM 模型文件（species.hmm）")
    pp.add_argument("genome", help="待预测基因组 FASTA")
    pp.add_argument("-o", "--output", help="输出 ZFF 路径（stdout 重定向）")
    _add_runtime_opts(pp)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:16s} {v}")
        return 0
    if "--schema" in args:
        print(json.dumps(SnapSkill().schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SnapSkill()
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

    # stdout 类子命令落到 --output 文件
    if ns.subcommand in STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)

    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
