#!/usr/bin/env python3
"""bless native 标准入口驱动（BLESS / BLESS 2，Bloom-filter NGS reads 错误修正）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py correct -1 reads_1.fastq -2 reads_2.fastq -k 21 -p out/illumina --threads 8
   python main.py correct -r single.fastq -k 21 -p out/single --notrim
   python main.py correct -1 reads_1.fastq -2 reads_2.fastq -k 21 -p out/pe -l db_prefix
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py correct ... --dry-run   # 只打印构建出的命令，不执行

命令逻辑（bless 官方 wiki https://sourceforge.net/p/bless-ec/wiki/Home/ + 用户文档示例）：
  bless 为单条命令工具（无子命令/无 --help/-v；无参运行即打印全部选项）：
    ./bless -read1 <R1> -read2 <R2> -prefix <输出目录名>/<文件前缀> -kmerlength <k>   # 双端
    ./bless -read <fastq> -prefix <输出目录名>/<文件前缀> -kmerlength <k>            # 单端
    可选：-notrim（不修剪末端，官方默认自 V0.13 起修剪）、-load <prefix>（载入既有
    Bloom filter 转储 <prefix>.bf.data/.bf.size，跳过 k-mer 计数）、-smpthread <N>
    （OpenMP 线程数，默认 = SMP 节点核数；跨节点并行用 mpirun 启动）。
  产物：双端 <prefix>.1.corrected.fastq + <prefix>.2.corrected.fastq（用户文档命名）；
  运行注意事项（用户文档）：BLESS 编译需高版本 GCC + MPICH；运行时依赖当前目录下
  kmc/bin/kmc（先 mkdir -p kmc/bin; cp <安装目录>/kmc/bin/kmc kmc/bin/）；主机名解析
  异常时可 `hostname localhost` 修复后运行。
  ⚠️ 参数白名单只收录官方 wiki / 用户文档可证选项（-read/-read1/-read2/-prefix/-kmerlength/
  -notrim/-load/-smpthread）；其它选项（如无参帮助输出里的附加开关，未下载源码核实）请用
  --extra-args 透传。
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

# 子命令语义清单（用于 --list-commands 与 Schema description）。
# bless 原生无子命令；为对齐 SkillBase 分发接口/Agent 路由，用单一 correct 子命令承载整条官方 CLI。
SUBCOMMANDS = {
    "correct": "运行 bless 错误修正主程序（官方单条 CLI：-read1/-read2 双端 或 -read 单端；"
               "-kmerlength/-prefix 必给；-notrim/-load 可选；-smpthread 自动注入）",
}

class BlessSkill(base.SkillBase):
    software = "bless"
    binary = "bless"

    def _resolve_binary(self) -> str:
        """解析 NGS BLESS 可执行文件（同名异义防护）。

        ⚠️ 同名异义真实存在：macOS 自带 /usr/sbin/bless（设置启动盘的苹果系统工具），
        conda-forge/bless 则是 Python CLI 日志包 —— 都会 shadow NGS BLESS。
        校验法：NGS bless 无 --help/-v，无参运行即打印含 -kmerlength/-prefix 的全部选项。
        """
        import subprocess
        bin_name = self.binary or self.software
        path = base.which(bin_name)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{bin_name}'，请先通过 native/install.sh --method source "
                "（源码编译）或 Docker/Apptainer（native/Dockerfile / Apptainer.def）安装。"
            )
        try:
            proc = subprocess.run([path], capture_output=True, text=True, timeout=20)
            out = (proc.stdout or "") + (proc.stderr or "")
        except Exception:
            out = ""
        if "-kmerlength" not in out:
            raise RuntimeError(
                f"可执行文件 '{path}' 不是 NGS BLESS（无参输出未见 -kmerlength；可能命中"
                "同名异义命令，如 macOS /usr/sbin/bless 启动盘工具、conda-forge/bless 日志包）。"
                "请用 native/install.sh --method source 安装 NGS bless，并确保其 bin 目录在 PATH 中"
                "优先于系统目录；或加 --dry-run 只做命令构建。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 bless 命令行（correct → 官方单条 bless 命令）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        # 输入三态互斥：双端（read1+read2）> 单端（read）> 报错
        has_pe = bool(kw.get("read1")) or bool(kw.get("read2"))
        has_se = bool(kw.get("read"))
        if has_pe and has_se:
            raise ValueError("输入互斥：-read（单端）与 -read1/-read2（双端）只能选一种")
        if has_pe and not (kw.get("read1") and kw.get("read2")):
            raise ValueError("paired-end 模式需要同时提供 read1（-1）与 read2（-2）")

        cmd: list[str] = [binary]
        if has_pe:
            cmd += ["-read1", str(kw["read1"]), "-read2", str(kw["read2"])]
        elif has_se:
            cmd += ["-read", str(kw["read"])]
        else:
            raise ValueError("correct 需要输入：-1/-2（双端）或 -r（单端）")

        if not kw.get("prefix"):
            raise ValueError("correct 需要 -p/--prefix（输出前缀 <目录名>/<文件前缀>）")
        cmd += ["-kmerlength", str(kw.get("kmerlength", 21))]
        cmd += ["-prefix", str(kw["prefix"])]

        if kw.get("notrim"):
            cmd.append("-notrim")
        if kw.get("load"):
            cmd += ["-load", str(kw["load"])]

        # 线程注入：用户显式 --threads / optimization.per_subcommand_threads → -smpthread
        cmd += ["-smpthread", str(threads)]

        # 高级透传（慎用；白名单外选项由此进入）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射到 bless -smpthread）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（KMC 计数与中间文件的临时目录）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="bless-skill",
        description="bless native 技能驱动（BLESS/BLESS 2 Bloom-filter reads 错误修正；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("correct", help=SUBCOMMANDS["correct"])
    # 输入三态（短参友好 + 长参白名单）
    pc.add_argument("-r", "--read", help="单端（或已合并双端）FASTQ 输入")
    pc.add_argument("-1", "--read1", dest="read1", help="双端 R1 FASTQ（与 -2 成对）")
    pc.add_argument("-2", "--read2", dest="read2", help="双端 R2 FASTQ（与 -1 成对）")
    pc.add_argument("-k", "--kmerlength", type=int, default=21,
                    help="k-mer 长度（默认 21；BLESS1 建议奇数，V0.20 起支持偶数）")
    pc.add_argument("-p", "--prefix", help="输出前缀 <输出目录名>/<文件前缀>（必填）")
    pc.add_argument("--notrim", action="store_true", help="不进行末端修剪（官方默认修剪）")
    pc.add_argument("-l", "--load", help="载入既有 Bloom filter 转储前缀（跳过 k-mer 计数）")
    pc.add_argument("--extra-args", help="透传给 bless 的额外参数（慎用）")
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
        skill = BlessSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = BlessSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    if dry_run:
        # --dry-run 只做命令构建自检，不要求真实二进制已安装
        skill._resolve_binary = lambda: "bless"

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
