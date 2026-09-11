#!/usr/bin/env python3
"""hmmer2（HMMER 2.x 遗留版）native 标准入口驱动。

HMMER 2.x 是基于 profile HMM 的序列同源检索 / 序列谱建库经典工具套件（2003 年前后的遗留版本），
CLI 与输出格式均与 HMMER 3.x 不同；它是 RNAmmer 1.2、旧版 antiSMASH 等工具的必需运行依赖
（这些工具对 HMMER 版本敏感，须用 2.x）。

本驱动为软件模块 modules/hmmer/ 的 HMMER 2.x 遗留版实现（位于 modules/hmmer/native2/，与
HMMER 3.x 现行实现 modules/hmmer/native/ 共用同一软件级 meta 与 README）；HMMER 3.x 用法见
本模块 README 的 3.x 章节。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py hmmbuild family.hmm family.sto -n teach_family
   python main.py hmmsearch family.hmm proteins.fa -E 10 --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

二进制命名（关键，见 meta.yaml software_versions）：
- bioconda hmmer2 包内所有工具**带 2 后缀**（hmmbuild2 / hmmsearch2 / …），以避免与 HMMER3 冲突；
- 上游源码自编译为无后缀（hmmbuild / hmmsearch）；Debian 包为 hmm2build / hmm2search 前缀。
故本驱动按**多候选名探测**：hmmbuild2→hmmbuild→hmm2build、hmmsearch2→hmmsearch→hmm2search。

HMMER2 CLI 语义（本驱动对齐，与 HMMER3 不同）：
- hmmbuild [options] <hmmfile> <alignfile>：由 MSA 训练 HMMER2 profile HMM（-n 命名、-F 覆盖）；
  **无 --cpu / 无 --tblout**（HMMER2 hmmbuild 无并行）
- hmmsearch [options] <hmmfile> <seqfile>：用 HMM 检索序列库（-E/-T 阈值、-A 比对条数、--cpu 并行）；
  **2.x 无 --tblout**（那是 HMMER3 的选项），主输出走 stdout，由驱动直接透传
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
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
    "hmmbuild": "hmmbuild：由多序列比对（MSA）训练 HMMER2 profile HMM（官方 <hmmfile> <alignfile>）",
    "hmmsearch": "hmmsearch：用 profile HMM 检索序列库（官方 <hmmfile> <seqfile>；HMMER2 无 --tblout，输出走 stdout）",
}

# 每个逻辑工具的候选可执行名（bioconda 2 后缀 → 上游无后缀 → Debian 前缀），按优先级探测
BINARY_CANDIDATES = {
    "hmmbuild": ("hmmbuild2", "hmmbuild", "hmm2build"),
    "hmmsearch": ("hmmsearch2", "hmmsearch", "hmm2search"),
}


class Hmmer2Skill(base.SkillBase):
    software = "hmmer2"
    binary = "hmmsearch2"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/hmmer/meta.yaml（本实现在 native2/ 下，
        # 与 native/ 共用同一软件级 meta），显式指向它，使 --schema / per_subcommand_threads 真正生效。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _is_hmmer2(self, path: str) -> bool:
        """运行 `<bin> -h` 并确认输出为 HMMER 2.（避免误用同名的 HMMER3 hmmsearch/hmmbuild）。"""
        try:
            proc = subprocess.run(
                [path, "-h"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, check=False, timeout=30,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        return bool(re.search(r"HMMER 2\.", proc.stdout or ""))

    def _resolve_tool(self, logical: str) -> str:
        """按多候选名探测 HMMER2 可执行文件（hmmsearch2 → hmmsearch → hmm2search）。

        每个候选都校验 `-h` 输出确为 'HMMER 2.'——因为无后缀的 hmmsearch/hmmbuild 与 HMMER3
        同名，若本机只装了 HMMER3 会误命中，故必须按版本核对后才接受。
        """
        candidates = BINARY_CANDIDATES[logical]
        tried: list[str] = []
        for candidate in candidates:
            path = shutil.which(candidate)
            if not path:
                continue
            tried.append(candidate)
            if self._is_hmmer2(path):
                return path
        names = " / ".join(candidates)
        detail = ("（已找到候选 %s，但其 -h 输出非 'HMMER 2.'，疑似 HMMER 3.x，已拒绝）"
                  % " / ".join(tried)) if tried else ""
        raise RuntimeError(
            f"未找到 HMMER2 可执行文件 '{logical}'（候选名: {names}）{detail}。"
            "请先通过 Conda/Docker/Apptainer 安装：bioconda hmmer2=2.3.2（包内二进制带 2 后缀，"
            "如 hmmsearch2/hmmbuild2，可与 HMMER3 并存），或 native/install.sh 双路线安装。"
            "注意勿与 HMMER 3.x 混淆（3.x 见本模块 native/）。"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 HMMER2 命令行。"""
        if subcommand == "hmmbuild":
            binary = self._resolve_tool("hmmbuild")
            hmm_out = kw.get("hmm_out")
            msa = kw.get("msa")
            if not hmm_out:
                raise RuntimeError("hmmbuild 需要 hmm_out（官方位置参数 <hmmfile>，如 family.hmm）")
            if not msa:
                raise RuntimeError("hmmbuild 需要 msa（官方位置参数 <alignfile>，多序列比对文件）")
            cmd: list[str] = [binary]
            name = kw.get("name")
            if name:
                cmd += ["-n", str(name)]
            if kw.get("force"):
                cmd += ["-F"]
            # HMMER2 hmmbuild 无线程参数（--threads 仅协议位，不注入）
            # 官方用法：hmmbuild [options] <hmmfile> <alignfile>
            cmd += [str(hmm_out), str(msa)]

        elif subcommand == "hmmsearch":
            binary = self._resolve_tool("hmmsearch")
            hmm = kw.get("hmm")
            seqdb = kw.get("seqdb")
            if not hmm:
                raise RuntimeError("hmmsearch 需要 hmm（官方位置参数 <hmmfile>，profile HMM 文件）")
            if not seqdb:
                raise RuntimeError("hmmsearch 需要 seqdb（官方位置参数 <seqfile>，目标序列库）")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            # HMMER2 hmmsearch 支持 --cpu <n>（专家选项）
            cmd = [binary, "--cpu", str(threads)]
            if kw.get("evalue") is not None:
                cmd += ["-E", str(kw["evalue"])]
            if kw.get("bit_score") is not None:
                cmd += ["-T", str(kw["bit_score"])]
            if kw.get("alignment") is not None:
                cmd += ["-A", str(kw["alignment"])]
            # 官方用法：hmmsearch [options] <hmmfile> <seqfile>
            cmd += [str(hmm), str(seqdb)]

        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hmmer2-skill",
        description="hmmer2（HMMER 2.x 遗留版）native 技能驱动（profile HMM 建库与检索；RNAmmer/旧 antiSMASH 依赖）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # hmmbuild <hmmfile> <alignfile>
    pb = sub.add_parser("hmmbuild", help=SUBCOMMANDS["hmmbuild"])
    pb.add_argument("hmm_out", help="输出 HMM 文件（官方位置参数 <hmmfile>）")
    pb.add_argument("msa", help="输入多序列比对 MSA（官方位置参数 <alignfile>，Stockholm/SELEX/afa 等）")
    pb.add_argument("-n", "--name", help="给 HMM 命名（-n <s>；缺省取 MSA 名）")
    pb.add_argument("-F", "--force", action="store_true", help="强制覆盖已存在的 HMM 文件（-F）")
    pb.add_argument("--extra-args", dest="extra_args", help="透传给 hmmbuild 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    # hmmsearch [options] <hmmfile> <seqfile>
    ps = sub.add_parser("hmmsearch", help=SUBCOMMANDS["hmmsearch"])
    ps.add_argument("hmm", help="profile HMM 文件（官方位置参数 <hmmfile>）")
    ps.add_argument("seqdb", help="目标序列库（官方位置参数 <seqfile>，蛋白序列 FASTA 等）")
    ps.add_argument("-E", "--evalue", type=float, help="序列 E-value 阈值（-E <x>；HMMER2 默认 10.0）")
    ps.add_argument("-T", "--bit-score", dest="bit_score", type=float, help="序列位分阈值（-T <x>；默认负无穷）")
    ps.add_argument("-A", "--alignment", type=int, help="比对输出的最优结构域条数（-A <n>；-A0 关闭）")
    ps.add_argument("--extra-args", dest="extra_args", help="透传给 hmmsearch 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（hmmsearch 注入为 --cpu N；hmmbuild 协议位不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Hmmer2Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Hmmer2Skill()
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

    # hmmsearch/hmmbuild 主输出走 stdout，直接透传
    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
