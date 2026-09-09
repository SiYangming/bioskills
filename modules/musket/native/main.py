#!/usr/bin/env python3
"""musket native 标准入口驱动（继承 base.SkillBase）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py correct --kmer-size 21 --est-kmer-count 50000000 --omulti out -p 4 --inorder \
       --reads f1.fastq f2.fastq
   python main.py correct --kmer-size 21 --est-kmer-count 536870912 -o merged.fastq -p 8 \
       --reads lib1.fastq lib2.fastq
   python main.py correct --omulti out --inorder --reads f1_1.fastq f1_2.fastq f2_1.fastq f2_2.fastq
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py correct ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑（Musket v1.1 官方 README = https://musket.sourceforge.net/homepage.htm，
2026-09-08 核实参数全表；上游为单条命令工具、无官方子命令/--help/--version）：
  musket [-k <kmer_size> <est_kmer_count>] [-o <single_out> | -omulti <prefix>]
         [-p <threads>] [-inorder] [-lowercase] [-zlib <n>] [-maxtrim <n>]
         [-maxbuff <n>] [-multik <0|1>] [-maxerr <n>] [-maxiter <n>] [-minmulti <n>]
         <input1.fastq/fasta[.gz]> <input2...>

语义要点（以官方 README 为准，勿臆造）：
  -k 后跟两值：k-mer 长度（默认 21，Makefile 宏 MAX_KMER_SIZE 默认 28 → >28 需改宏重编译）+
    估计的不同 k-mer 总数（默认 536870912；不影响正确性，只平衡 Bloom filter 与 hash table
    内存占用——教学文档所称「50000000 哈希表大小」即此估计值）。
  -o 与 -omulti 互斥；-omulti <prefix> 输出 <prefix>.0/.1/.2...（第 i 输入 ↔ 第 i-1 输出）。
  -p 官方要求 >=2（默认 2）；-inorder 保持输出顺序与输入一致（1.0.5 起 PE 修正只需 -omulti+
  -inorder）。
--threads 自动注入官方 -p（显式 --threads 优先，缺省取 meta optimization 默认 4）。
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
    "correct": "k-mer 谱多阶段错误修正（官方主流程：musket [-k <kmer> <est>] "
               "[-o <file>|-omulti <prefix>] -p <threads> [-inorder] ... <reads...>；"
               "--threads 自动注入 -p）",
}

# 官方默认值（musket.sourceforge.net/homepage.htm 参数表）
DEFAULT_KMER_SIZE = 21
DEFAULT_EST_KMER_COUNT = 536870912
# Makefile 宏 MAX_KMER_SIZE 默认值（官方 Installation and Usage 节；更大的 k 需改宏重编译）
DEFAULT_MAX_KMER_SIZE = 28


class MusketSkill(base.SkillBase):
    software = "musket"
    binary = "musket"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        if isinstance(per, dict):
            return int(per.get(subcommand, per.get("default", self.cpus)))
        return int(self.cpus)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 musket 命令行（对齐官方 v1.1 主流程）。"""
        if subcommand != "correct":
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()

        # 输入文件（一个或多个文库；FASTA/FASTQ，支持 gzip）
        reads = kw.get("reads")
        if not reads:
            raise ValueError("correct 需要 --reads <file...>（一个或多个 FASTA/FASTQ[.gz] 输入文库）")
        if isinstance(reads, str):
            reads = shlex.split(reads)
        reads = [str(r) for r in reads if str(r)]
        if not reads:
            raise ValueError("correct 需要至少一个输入文库文件（--reads）")

        cmd: list[str] = [binary]

        # -k <kmer_size> <est_kmer_count>：官方两值参数；任一显式给出即整组注入（缺省值补齐官方默认）
        kmer_size = kw.get("kmer_size")
        est_count = kw.get("est_kmer_count")
        if kmer_size is not None or est_count is not None:
            ksize = int(kmer_size) if kmer_size is not None else DEFAULT_KMER_SIZE
            est = int(est_count) if est_count is not None else DEFAULT_EST_KMER_COUNT
            if ksize <= 0 or est <= 0:
                raise ValueError("-k 的两个值必须为正整数（kmer_size / est_kmer_count）")
            if ksize > DEFAULT_MAX_KMER_SIZE:
                raise ValueError(
                    f"kmer_size={ksize} 超过官方 Makefile 宏 MAX_KMER_SIZE 默认 {DEFAULT_MAX_KMER_SIZE}；"
                    "更大的 k 需修改 Makefile 的 MAX_KMER_SIZE 并重新编译 musket（勿臆造支持上限）"
                )
            cmd += ["-k", str(ksize), str(est)]

        # -o / -omulti 互斥（官方 mutually exclusive）
        output = kw.get("output")
        omulti = kw.get("omulti")
        if output and omulti:
            raise ValueError("-o/--output 与 --omulti 互斥（官方 README：mutually exclusive），只能二选一")
        if output:
            cmd += ["-o", str(output)]
        elif omulti:
            cmd += ["-omulti", str(omulti)]

        # -p 线程（自动注入；官方要求 >=2）
        threads = self._effective_threads("correct", kw.get("threads"))
        if threads < 2:
            raise ValueError(f"musket -p 官方要求 >=2（收到 threads={threads}），请增大 --threads")
        cmd += ["-p", str(threads)]

        # 布尔开关（仅显式给出时注入；-multik 官方 <bool> 参数需显式取值 1）
        for flag in ("inorder", "lowercase"):
            if kw.get(flag):
                cmd += [f"-{flag}"]
        if kw.get("multik"):
            cmd += ["-multik", "1"]

        # 整型白名单（仅显式给出时注入；数值取值含义以官方 README 为准，驱动不臆造语义）
        for key, flag in (
            ("zlib", "-zlib"),
            ("maxtrim", "-maxtrim"),
            ("maxbuff", "-maxbuff"),
            ("maxerr", "-maxerr"),
            ("maxiter", "-maxiter"),
            ("minmulti", "-minmulti"),
        ):
            val = kw.get(key)
            if val is not None:
                cmd += [flag, str(int(val))]

        # 输入文库文件追加到命令末尾（官方位置参数形态）
        cmd += reads

        # 白名单外的上游参数（高级用法）原样透传，追加到命令末尾
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖线程数（注入官方 -p；官方要求 >=2）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="musket-skill",
        description="musket native 技能驱动（correct：k-mer 谱多阶段错误修正；对齐官方 v1.1 主流程）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("correct", help=SUBCOMMANDS["correct"])
    pc.add_argument("--reads", nargs="+", required=True,
                    help="一个或多个输入文库文件（FASTA/FASTQ，支持 gzip 压缩；多文库时建议配合 --omulti/--inorder）")
    pc.add_argument("--kmer-size", type=int, dest="kmer_size", default=None,
                    help=f"-k 第一值：k-mer 长度（官方默认 {DEFAULT_KMER_SIZE}；Makefile MAX_KMER_SIZE 默认 "
                         f"{DEFAULT_MAX_KMER_SIZE}，更大的 k 需改宏重编译）")
    pc.add_argument("--est-kmer-count", type=int, dest="est_kmer_count", default=None,
                    help=f"-k 第二值：估计的不同 k-mer 总数（官方默认 {DEFAULT_EST_KMER_COUNT}；只平衡 "
                         "Bloom filter/hash 内存、不影响正确性）")
    out_group = pc.add_mutually_exclusive_group()
    out_group.add_argument("-o", "--output", dest="output", default=None,
                           help="单一输出文件名（全部 reads 合并写入；与 --omulti 互斥）")
    out_group.add_argument("--omulti", dest="omulti", default=None,
                           help="多路输出前缀（第 i 输入 → <prefix>.i-1，从 0 起）")
    pc.add_argument("--inorder", action="store_true", default=False,
                    help="保持 reads 输出顺序与输入一致（paired-end 多文库修正必需；官方自 1.0.5 起以 "
                         "-inorder 取代 -paired）")
    pc.add_argument("--lowercase", action="store_true", default=False,
                    help="修正后的碱基以小写输出（官方自 1.0.6 起；缺省大写）")
    pc.add_argument("--multik", action="store_true", default=False,
                    help="启用多 k-mer 大小（advanced，官方 -multik <bool>；开启后 -minmulti 不适用）")
    pc.add_argument("--zlib", type=int, default=None, help="zlib 压缩输出（官方默认 0=不压缩）")
    pc.add_argument("--maxtrim", type=int, default=None, help="最多可修剪的末端碱基数（默认 0=不修剪）")
    pc.add_argument("--maxbuff", type=int, default=None,
                    help="每 worker 消息缓冲区容量（advanced，官方默认 1024）")
    pc.add_argument("--maxerr", type=int, default=None,
                    help="任意 #k 长度区域内允许的最大突变数（advanced，官方默认 4）")
    pc.add_argument("--maxiter", type=int, default=None,
                    help="每个 k-mer 大小的最大修正迭代数（advanced，官方默认 2）")
    pc.add_argument("--minmulti", type=int, default=None,
                    help="正确 k-mer 的最低 multiplicity（advanced，仅未启用 multik 时适用，默认 0）")
    pc.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外的上游参数原样透传（高级用法，慎用；用引号包裹）")
    _add_runtime_opts(pc)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = MusketSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MusketSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    if dry_run:
        # --dry-run 只做命令构建自检，不要求真实二进制已安装
        skill._resolve_binary = lambda: "musket"  # type: ignore[method-assign]

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
