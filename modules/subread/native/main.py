#!/usr/bin/env python3
"""subread native 标准入口驱动（Subread / featureCounts）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py featureCounts -a genome.gtf -o counts.txt -T 8 -p sample.bam
   python main.py subread-align -i subread_index -r reads_1.fq -R reads_2.fq -o aln.bam --threads 8
   python main.py subjunc -i subread_index -r reads_1.fq -R reads_2.fq -o junction.bam --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐官方 subread / featureCounts 手册）：
  featureCounts  featureCounts -T N [-p] -t exon -g gene_id [-s 0] [-Q n] -a <gtf> -o <out> <bam...>
  subread-align  subread-align -i <index> -r <reads1> [-R <reads2>] -o <out> -T N [-t 0]
  subjunc        subjunc -i <index> -r <reads1> [-R <reads2>] -o <out> -T N
三个子命令分属同一 subread 包内的三个可执行文件，共享线程注入（-T）与临时目录优化。
"""

from __future__ import annotations

import argparse
import json
import shlex
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
    "featureCounts": "RNA-seq reads 基因/外显子水平计数（-a 注释 -o 输出 <bam...>；-T 自动注入）",
    "subread-align": "Subread gapped 基因组比对（-i 索引 -r reads1 [-R reads2] -o 输出）",
    "subjunc": "剪接感知比对 + 剪接位点/融合检测（-i 索引 -r reads1 [-R reads2] -o 输出）",
}

# 子命令 -> subread 包内实际可执行文件名
BINARY_FOR = {
    "featureCounts": "featureCounts",
    "subread-align": "subread-align",
    "subjunc": "subjunc",
}


class SubreadSkill(base.SkillBase):
    software = "subread"
    binary = "featureCounts"

    def _resolve_binary(self, name: str | None = None) -> str:
        """按子命令解析 subread 包内的实际可执行文件（惰性解析，测试可 monkeypatch）。"""
        bin_name = name or self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 Conda/Docker/Apptainer 安装 subread"
                "（featureCounts / subread-align / subjunc 同属该包）。"
            )
        return path

    def _as_list(self, value) -> list[str]:
        if value is None:
            return []
        if isinstance(value, (list, tuple)):
            return [str(v) for v in value]
        return [str(value)]

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 subread 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

        binary = self._resolve_binary(BINARY_FOR[subcommand])
        threads = self._effective_threads(subcommand, kw.get("threads"))
        cmd: list[str] = [binary]

        if subcommand == "featureCounts":
            gtf = kw.get("gtf")
            out = kw.get("output")
            bams = self._as_list(kw.get("bam"))
            if not gtf:
                raise ValueError("featureCounts 缺少必填参数 gtf（-a 参考注释 GTF）")
            if not out:
                raise ValueError("featureCounts 缺少必填参数 output（-o 计数表）")
            if not bams:
                raise ValueError("featureCounts 缺少必填参数 bam（至少一个输入 BAM）")
            cmd += ["-T", str(threads)]
            if kw.get("paired"):
                cmd.append("-p")
            cmd += ["-t", str(kw.get("feature_type") or "exon")]
            cmd += ["-g", str(kw.get("group_attribute") or "gene_id")]
            if kw.get("stranded") is not None:
                cmd += ["-s", str(kw["stranded"])]
            if kw.get("min_mapq") is not None:
                cmd += ["-Q", str(kw["min_mapq"])]
            cmd += ["-a", str(gtf), "-o", str(out)]
            cmd += bams
        else:
            # subread-align / subjunc 共用 -i/-r/-R/-o/-T
            index = kw.get("index")
            reads = kw.get("reads")
            out = kw.get("output")
            if not index:
                raise ValueError(f"{subcommand} 缺少必填参数 index（-i Subread 索引）")
            if not reads:
                raise ValueError(f"{subcommand} 缺少必填参数 reads（-r reads）")
            if not out:
                raise ValueError(f"{subcommand} 缺少必填参数 output（-o 输出）")
            cmd += ["-i", str(index), "-r", str(reads)]
            if kw.get("reads2"):
                cmd += ["-R", str(kw["reads2"])]
            if subcommand == "subread-align" and kw.get("read_type") is not None:
                cmd += ["-t", str(kw["read_type"])]
            cmd += ["-o", str(out), "-T", str(threads)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射到 subread -T）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="subread-skill",
        description="subread native 技能驱动（featureCounts / subread-align / subjunc；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # featureCounts
    pc = sub.add_parser("featureCounts", help=SUBCOMMANDS["featureCounts"])
    pc.add_argument("bam", nargs="+", help="输入比对 BAM（可多个）")
    pc.add_argument("-a", "--gtf", required=True, help="参考注释 GTF（-a）")
    pc.add_argument("-o", "--output", required=True, help="输出计数表（-o）")
    pc.add_argument("-t", "--feature-type", default="exon", help="计数特征类型（-t，默认 exon）")
    pc.add_argument("-g", "--group-attribute", default="gene_id",
                    help="分组属性（-g，默认 gene_id）")
    pc.add_argument("-s", "--stranded", type=int, default=0,
                    help="链特异性：0=非链特异，1=正向，2=反向（-s）")
    pc.add_argument("-p", "--paired", action="store_true", help="按片段计数（-p，双端）")
    pc.add_argument("-Q", "--min-mapq", type=int, help="最小比对质量（-Q）")
    pc.add_argument("--extra-args", help="透传给 featureCounts 的额外参数（慎用）")
    _add_runtime_opts(pc)

    # subread-align / subjunc 共用参数形态
    for name in ("subread-align", "subjunc"):
        pa = sub.add_parser(name, help=SUBCOMMANDS[name])
        pa.add_argument("-i", "--index", required=True, help="Subread 索引前缀（-i）")
        pa.add_argument("-r", "--reads", required=True, help="单端 / 双端 mate1 reads（-r）")
        pa.add_argument("-R", "--reads2", help="双端 mate2 reads（-R）")
        pa.add_argument("-o", "--output", required=True, help="输出比对结果（-o）")
        if name == "subread-align":
            pa.add_argument("-t", "--read-type", type=int, default=0,
                            help="数据类型：0=RNA-seq，1=gDNA（-t）")
        pa.add_argument("--extra-args", help=f"透传给 {name} 的额外参数（慎用）")
        _add_runtime_opts(pa)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:14s} {v}")
        return 0
    if "--schema" in args:
        skill = SubreadSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SubreadSkill()
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
