#!/usr/bin/env python3
"""isoseq3 native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py refine --bam input.bam --primers primers.fasta --outdir out --prefix sample --threads 8
   python main.py refine input.bam primers.fasta out/refined.bam --require-polya
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑迁移自 snakemake.smk/isoseq.smk/isoseq.py/isoseq3_refine.py
与 workflow/modules/isoseq3/snakemake/isoseq3.smk：isoseq3 refine [-j N] [--require-polya] <bam> <primers> <out.bam>。
注意：bioconda 包名为 isoseq，可执行二进制为 isoseq3。
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
    "refine": "去除 polyA 尾与人工连接体（Iso-Seq 第三步，lima 产物 -> 精炼 reads）",
}


class IsoSeq3Skill(base.SkillBase):
    software = "isoseq3"
    binary = "isoseq3"  # conda 包 isoseq 提供的套件入口

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 isoseq3 refine 命令行。"""
        if subcommand != "refine":
            raise ValueError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        cmd: list[str] = [binary, "refine"]

        bam = kw.get("bam") or kw.get("input")
        primers = kw.get("primers")
        if not bam:
            raise ValueError("缺少必填参数 bam（lima 清理后的输入 BAM）")
        if not primers:
            raise ValueError("缺少必填参数 primers（引物 FASTA）")

        # 线程注入（-j 与 --num-threads 等价）
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd += ["-j", str(threads)]

        # polyA 相关（require_polya 默认开启；显式传 False 则去掉）
        if kw.get("require_polya", True):
            cmd.append("--require-polya")
        if kw.get("min_polya_length") is not None:
            cmd += ["--min-polya-length", str(kw["min_polya_length"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        # 输出路径：显式 output > outdir/prefix.bam
        out_bam = kw.get("output")
        if not out_bam:
            prefix = kw.get("prefix")
            if not prefix:
                prefix = Path(bam).name[:-4] if Path(bam).name.endswith(".bam") else Path(bam).stem
            outdir = kw.get("outdir")
            if outdir:
                outdir_path = Path(outdir)
            else:
                outdir_path = Path(bam).parent
            out_bam = str(outdir_path / f"{prefix}.bam")

        cmd += [str(bam), str(primers), out_bam]

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="isoseq3-skill",
        description="isoseq3 (refine) native 技能驱动（自动线程优化）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("refine", help=SUBCOMMANDS["refine"])
    pr.add_argument("--bam", help="输入 BAM（lima 清理后的 ccs BAM）")
    pr.add_argument("--input", help="输入 BAM 的别名")
    pr.add_argument("--primers", help="引物 FASTA 文件")
    pr.add_argument("-o", "--output", help="输出 BAM 路径（缺省自动生成）")
    pr.add_argument("-d", "--outdir", help="输出目录")
    pr.add_argument("--prefix", help="输出前缀（默认从 bam 文件名推断）")
    pr.add_argument("--require-polya", dest="require_polya", action="store_true", default=True,
                    help="仅保留检测到 polyA 尾的 reads（默认开启；配合 --no-require-polya 关闭）")
    pr.add_argument("--no-require-polya", dest="require_polya", action="store_false",
                    help="关闭 --require-polya")
    pr.add_argument("--min-polya-length", type=int, help="polyA 尾最小长度")
    pr.add_argument("--extra-args", help="透传给 isoseq3 refine 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pr)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = IsoSeq3Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = IsoSeq3Skill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    # isoseq3 refine 无 stdout 输出；stderr 直接透传
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
