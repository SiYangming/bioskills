#!/usr/bin/env python3
"""IGV native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py launch --genome hg18 --locus chr1:1000-2000 sample.bam sample.vcf
   python main.py batch --batch snapshot.txt --genome hg18 sample.bam
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑：
  launch   igv.sh [--genome <id|.genome>] [--locus <chr:start-end>] [files...]
  batch    igv.sh --batch <script> [--genome <id|.genome>] [--locus <chr:start-end>] [files...]
注意：IGV 是 Java 图形界面工具（需 Java 运行时 + DISPLAY），本驱动只做启动器与命令构造；
      JAVA_OPTS 由 optimization.env_vars 透传；IGV 单实例，--threads 仅供调度参考。
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
    "launch": "启动 IGV 图形界面（可选 --genome/--locus 与待加载文件）",
    "batch": "以 --batch <script> 运行 IGV 批处理脚本（可配合 --genome/--locus/文件）",
}


class IgvSkill(base.SkillBase):
    software = "igv"
    binary = "igv.sh"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 igv.sh 命令行（GUI / 批处理启动器）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        cmd: list[str] = [binary]

        if kw.get("genome"):
            cmd += ["--genome", str(kw["genome"])]
        if kw.get("locus"):
            cmd += ["--locus", str(kw["locus"])]

        batch = kw.get("batch")
        if subcommand == "batch":
            if not batch:
                raise ValueError("batch 缺少必填参数 batch（IGV 批处理脚本路径）")
            cmd += ["--batch", str(batch)]
        elif batch:
            cmd += ["--batch", str(batch)]

        # 待加载数据文件（positional，可多个）
        files = kw.get("files")
        if files:
            if isinstance(files, (list, tuple)):
                cmd += [str(f) for f in files]
            else:
                cmd.append(str(files))

        # 线程：IGV 单实例 GUI，仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（GUI 需 Java + DISPLAY；找不到二进制会抛错）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="igv-skill",
        description="IGV native 技能驱动（本地基因组浏览器 GUI / 批处理启动器）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pl = sub.add_parser("launch", help=SUBCOMMANDS["launch"])
    pl.add_argument("--genome", help="基因组 id（如 hg18）或 .genome/.fasta 路径")
    pl.add_argument("--locus", help="初始定位区间（如 scaffold_1:1000-2000）")
    pl.add_argument("files", nargs="*", help="启动时加载的数据文件（BAM/VCF/GFF3/BigWig/BED）")
    pl.add_argument("--extra-args", help="透传给 igv.sh 的额外参数")
    _add_runtime_opts(pl)

    pb = sub.add_parser("batch", help=SUBCOMMANDS["batch"])
    pb.add_argument("--batch", help="IGV 批处理脚本路径（batch 子命令必填）")
    pb.add_argument("--genome", help="基因组 id（如 hg18）或 .genome/.fasta 路径")
    pb.add_argument("--locus", help="初始定位区间（如 scaffold_1:1000-2000）")
    pb.add_argument("files", nargs="*", help="启动时加载的数据文件")
    pb.add_argument("--extra-args", help="透传给 igv.sh 的额外参数")
    _add_runtime_opts(pb)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（IGV 单实例 GUI，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = IgvSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = IgvSkill()
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
