#!/usr/bin/env python3
"""fastuniq native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -i illumina.list -o illumina.1.fastq -p illumina.2.fastq
   python main.py run --read1 R1.fastq --read2 R2.fastq -o R1.uniq.fastq -p R2.uniq.fastq
   python main.py run -i list.txt -t f -c 1 -o R1.uniq.fa -p R2.uniq.fa
   python main.py run -i list.txt -t p -o interleaved.uniq.fa
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py run ... --dry-run # 只打印构建出的命令，不执行

命令逻辑（FastUniq v1.1 官方 README.txt；来源：sourceforge FastUniq-1.1.tar.gz 内 README.txt
与 bioconda recipe 测试一致）：
  fastuniq -i <input_list> -t <q|f|p> -o <out1> [-p <out2>] [-c <0|1>]
  -i : 输入文件列表 [FILE IN]，每行一个 FASTQ/FASTA 文件；相邻两行、reads 顺序一致的文件属一对
       （2N 行 = N 对）；Maximum 1000 pairs
  -t : 输出序列格式 [q/f/p]，q=FASTQ 双文件（默认）/ f=FASTA 双文件 / p=FASTA 单文件
  -o : 第一输出文件 [FILE OUT]
  -p : 第二输出文件 [FILE OUT]（可选；仅 -t q/f 时需要）
  -c : 输出序列描述类型 [0/1]，0=原始描述（默认）/ 1=FastUniq 重新编号

⚠️ 与二手教程常见误解不同：FastUniq 的 -t 是「输出格式」而非临时目录、-c 是「描述类型」而非输出
目录（以官方 README 为准，勿臆造）。本驱动把 --tmpdir 仅用于进程 TMPDIR 环境注入与自动输入列表
的落盘位置；fastuniq 为单线程 C 程序，无 --threads 多线程参数（--threads 仅作占位接受、不注入）。
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
import tempfile
from pathlib import Path

# 让 main.py 既能被 skill-cli 导入（已加入 modules/ 路径），也能直接运行
_HERE = Path(__file__).resolve().parent
_SKILLS_ROOT = _HERE.parent.parent
if str(_SKILLS_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILLS_ROOT))

import base  # noqa: E402

# 子命令语义清单（用于 --list-commands 与 Schema description）
SUBCOMMANDS = {
    "run": "双端短读去重（写输入列表 → fastuniq -i list -t q|f|p -o R1.uniq [-p R2.uniq] [-c 0|1]；"
           "去 PCR/光学重复，无需参考基因组）",
}


class FastuniqSkill(base.SkillBase):
    software = "fastuniq"
    binary = "fastuniq"

    # -- 内部工具 ----------------------------------------------------------- #
    def _auto_write_list(self, read1: str, read2: str) -> str:
        """read1+read2 双文件自动写 2 行输入列表（FastUniq list 格式：每行一个文件）。

        列表写到 self.tmpdir 下，返回绝对路径；由调用方（main 非 dry-run 路径）负责在使用后删除，
        单测直接把 self.tmpdir 指向测试临时目录由 run_test.sh 的 trap 统一清理。
        """
        if not os.path.isdir(self.tmpdir):
            os.makedirs(self.tmpdir, exist_ok=True)
        fd, list_path = tempfile.mkstemp(prefix="fastuniq_list_", suffix=".txt", dir=self.tmpdir)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(os.path.abspath(str(read1)) + "\n")
            fh.write(os.path.abspath(str(read2)) + "\n")
        return list_path

    # -- 主构建接口 --------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据参数构建 fastuniq 命令行（对齐官方 v1.1 README：-i/-t/-o/-p/-c）。"""
        if subcommand != "run":
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()

        # 输入三选二：--list 列表文件 或 --read1+--read2 自动写列表
        list_file = kw.get("list")
        read1 = kw.get("read1")
        read2 = kw.get("read2")
        if list_file:
            list_path = str(list_file)
        elif read1 and read2:
            list_path = self._auto_write_list(read1, read2)
        elif read1 or read2:
            raise ValueError("--read1 与 --read2 必须成对给出（FastUniq 只处理配对 reads）")
        else:
            raise ValueError("需要输入：--list（输入列表文件）或 --read1+--read2（自动写列表）")

        fmt = str(kw.get("format") or "q").lower()
        if fmt not in ("q", "f", "p"):
            raise ValueError(f"-t/--format 仅支持 q|f|p（收到: {fmt}）")

        output1 = kw.get("output1")
        if not output1:
            raise ValueError("-o/--output1 必填（第一输出文件；-t p 模式为唯一输出文件）")

        cmd: list[str] = [binary, "-i", list_path, "-t", fmt, "-o", str(output1)]
        if fmt in ("q", "f"):
            output2 = kw.get("output2")
            if not output2:
                raise ValueError(
                    f"-t {fmt} 为双文件输出模式，-p/--output2 必填（第二输出文件）"
                )
            cmd += ["-p", str(output2)]
        # -c 描述类型：仅显式给定时注入（0=原始描述，1=重编号；默认 0）
        desc_type = kw.get("desc_type")
        if desc_type is not None:
            cmd += ["-c", str(int(desc_type))]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为子命令附加运行期覆盖项（线程/临时目录）。

    fastuniq 单线程：--threads 仅作占位接受、不注入命令（保持各模块 CLI 一致）；
    --tmpdir 用于进程 TMPDIR 环境注入 + 自动输入列表的落盘位置。
    """
    p.add_argument("--threads", type=int, help="占位：fastuniq 单线程无多线程参数（不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（进程 TMPDIR / 自动列表落盘位置）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fastuniq-skill",
        description="fastuniq native 技能驱动（双端短读去 PCR/光学重复；自动输入列表 + 官方 -i/-t/-o/-p/-c 参数）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-i", "--list", help="输入文件列表（每行一个 FASTQ/FASTA；相邻两行属一对，最多 1000 对）")
    pr.add_argument("--read1", help="双端 R1 FASTQ/FASTA（与 --read2 成对，自动写列表）")
    pr.add_argument("--read2", help="双端 R2 FASTQ/FASTA（与 --read1 成对，自动写列表）")
    pr.add_argument("-o", "--output1", help="第一输出文件（read1 去重结果；必填）")
    pr.add_argument("-p", "--output2", help="第二输出文件（read2 去重结果；-t q/f 双文件模式必填）")
    pr.add_argument("-t", "--format", choices=("q", "f", "p"), default="q",
                    help="输出格式：q=双 FASTQ（默认）/ f=双 FASTA / p=单 FASTA")
    pr.add_argument("-c", "--desc-type", type=int, choices=(0, 1), dest="desc_type",
                    help="输出描述类型：0=保留原始描述（默认）/ 1=FastUniq 重编号")
    pr.add_argument("--extra-args", help="透传给 fastuniq 的额外参数")
    _add_runtime_opts(pr)
    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = FastuniqSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FastuniqSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
    if dry_run:
        # --dry-run 只做命令构建自检，不要求真实二进制已安装
        skill._resolve_binary = lambda: "fastuniq"

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
