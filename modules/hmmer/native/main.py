#!/usr/bin/env python3
"""hmmer native 标准入口驱动（单一实现，覆盖 HMMER 3.x 现行版 + 2.x 遗留版）。

HMMER 是基于 profile hidden Markov model（profile HMM）做序列同源检索 / 结构域注释 /
序列谱建库的经典工具套件。本模块用一个 native 实现同时覆盖**两条版本线**，子命令按版本线区分：

HMMER 3.x 现行版（无后缀二进制，默认版本线）：
  hmmbuild   hmmbuild  <hmmfile_out> <msafile>   （由 MSA 训练 profile HMM，-n 命名、-o 汇总）
  hmmpress   hmmpress  <hmmfile>                 （按压为 .h3f/.h3i/.h3m/.h3p 索引；无并行）
  hmmsearch  hmmsearch <hmmfile> <seqdb>         （--tblout 表格、-o 主输出、-E 阈值）

HMMER 2.x 遗留版（2003 年前后旧版套件；RNAmmer 1.2 / 旧版 antiSMASH 的必需运行依赖）：
  hmmbuild2  hmmbuild  <hmmfile> <alignfile>     （-n 命名、-F 覆盖；2.x 无并行、无 --tblout）
  hmmsearch2 hmmsearch <hmmfile> <seqfile>       （-E/-T 阈值、-A 比对条数、--cpu 并行）

子命令名的 2 后缀与 bioconda hmmer2 包内二进制命名一致（hmmbuild2 / hmmsearch2），
借此与 3.x 的同名命令（hmmbuild / hmmsearch）区分，避免两条版本线冲突。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py hmmbuild family.hmm family.sto --threads 4          # 3.x 建谱
   python main.py hmmpress family.hmm                                 # 3.x 按压
   python main.py hmmsearch --hmm family.hmm proteins.fa --tblout hits.tbl -E 10
   python main.py hmmbuild2 family2.hmm family.sto -n teach_family    # 2.x 建谱
   python main.py hmmsearch2 family2.hmm proteins.fa -E 10 --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（--threads → HMMER 的 --cpu N）与临时目录（--tmpdir → TMPDIR）；
hmmpress（3.x 无并行）与 hmmbuild2（2.x 无并行）接受 --threads 但作为协议位不注入。

HMMER 2.x 二进制命名（关键，见 meta.yaml software_versions）：bioconda hmmer2 包内所有工具
**带 2 后缀**（hmmbuild2 / hmmsearch2 / …），上游源码自编译为无后缀，Debian 包为 hmm2 前缀；
故 2.x 子命令按**多候选名探测**：hmmbuild2→hmmbuild→hmm2build、hmmsearch2→hmmsearch→hmm2search，
并对候选做 `-h` 输出校验（须为 "HMMER 2."），避免误命中同名的 HMMER 3.x。
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
    "hmmbuild": "hmmbuild（HMMER 3.x）：由多序列比对（MSA）训练 profile HMM（官方 <hmmfile_out> <msafile>）",
    "hmmpress": "hmmpress（HMMER 3.x）：把 HMM 库按压为 .h3f/.h3i/.h3m/.h3p 索引（供 hmmscan 快速检索）",
    "hmmsearch": "hmmsearch（HMMER 3.x）：用 profile HMM 检索蛋白序列库（--tblout 表格、-o 主输出缺省 stdout）",
    "hmmbuild2": "hmmbuild2（HMMER 2.x 遗留版）：由 MSA 训练 HMMER2 profile HMM（-n 命名、-F 覆盖；2.x 无并行）",
    "hmmsearch2": "hmmsearch2（HMMER 2.x 遗留版）：用 HMM 检索序列库（-E/-T/-A；2.x 无 --tblout，输出走 stdout）",
}

# 版本线归属（3.x 无后缀 / 2.x 遗留版）
HMMER3_SUBCOMMANDS = ("hmmbuild", "hmmpress", "hmmsearch")
HMMER2_SUBCOMMANDS = ("hmmbuild2", "hmmsearch2")

# HMMER 2.x：每个逻辑工具的候选可执行名（bioconda 2 后缀 → 上游无后缀 → Debian 前缀），按优先级探测
BINARY_CANDIDATES_V2 = {
    "hmmbuild": ("hmmbuild2", "hmmbuild", "hmm2build"),
    "hmmsearch": ("hmmsearch2", "hmmsearch", "hmm2search"),
}


class HmmerSkill(base.SkillBase):
    software = "hmmer"
    binary = "hmmsearch"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/hmmer/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    # ------------------------------------------------------------------ #
    # 二进制解析
    # ------------------------------------------------------------------ #
    def _resolve_tool(self, tool: str) -> str:
        """解析 HMMER 3.x 配套可执行文件（hmmbuild/hmmpress/hmmsearch），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到 HMMER 3.x 可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda hmmer=3.4 / 官方 release 源码归档提供 hmmbuild/hmmpress/hmmsearch 等）。"
            )
        return path

    @staticmethod
    def _is_hmmer2(path: str) -> bool:
        """运行 `<bin> -h` 并确认输出为 HMMER 2.（避免误用同名的 HMMER3 hmmsearch/hmmbuild）。"""
        try:
            proc = subprocess.run(
                [path, "-h"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, check=False, timeout=30,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        return bool(re.search(r"HMMER 2\.", proc.stdout or ""))

    def _resolve_tool_v2(self, logical: str) -> str:
        """按多候选名探测 HMMER 2.x 可执行文件（hmmsearch2 → hmmsearch → hmm2search）。

        每个候选都校验 `-h` 输出确为 'HMMER 2.'——因为无后缀的 hmmsearch/hmmbuild 与 HMMER3
        同名，若本机只装了 HMMER3 会误命中，故必须按版本核对后才接受。
        """
        candidates = BINARY_CANDIDATES_V2[logical]
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
            "如 hmmsearch2/hmmbuild2，可与 HMMER3 并存），或 native/install.sh --line 2 安装。"
            "注意勿与 HMMER 3.x 混淆（3.x 用无后缀子命令 hmmbuild/hmmsearch）。"
        )

    # ------------------------------------------------------------------ #
    # 命令构建
    # ------------------------------------------------------------------ #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 HMMER 命令行（自动按版本线分派）。"""
        if subcommand in HMMER3_SUBCOMMANDS:
            cmd = self._build_v3(subcommand, **kw)
        elif subcommand in HMMER2_SUBCOMMANDS:
            cmd = self._build_v2(subcommand, **kw)
        else:
            raise RuntimeError(f"未知子命令: {subcommand}")

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def _build_v3(self, subcommand: str, **kw) -> list[str]:
        """HMMER 3.x（无后缀二进制）命令行构建。"""
        threads = self._effective_threads(subcommand, kw.get("threads"))

        if subcommand == "hmmbuild":
            binary = self._resolve_tool("hmmbuild")
            hmm_out = kw.get("hmm_out")
            msa = kw.get("msa")
            if not hmm_out:
                raise RuntimeError("hmmbuild 需要 hmm_out（官方位置参数 <hmmfile_out>，如 family.hmm）")
            if not msa:
                raise RuntimeError("hmmbuild 需要 msa（官方位置参数 <msafile>，多序列比对文件）")
            cmd: list[str] = [binary]
            name = kw.get("name")
            if name:
                cmd += ["-n", str(name)]
            output = kw.get("output")
            if output:
                cmd += ["-o", str(output)]
            cmd += ["--cpu", str(threads)]
            # 官方用法：hmmbuild [options] <hmmfile_out> <msafile>
            cmd += [str(hmm_out), str(msa)]

        elif subcommand == "hmmpress":
            binary = self._resolve_tool("hmmpress")
            hmm = kw.get("hmm")
            if not hmm:
                raise RuntimeError("hmmpress 需要 hmm（官方位置参数 <hmmfile>，待按压的 HMM 文件）")
            cmd = [binary]
            if kw.get("force"):
                cmd += ["-f"]
            # 官方用法：hmmpress [-options] <hmmfile>（无并行，--cpu 不适用）
            cmd += [str(hmm)]

        else:  # hmmsearch
            binary = self._resolve_tool("hmmsearch")
            hmm = kw.get("hmm")
            seqdb = kw.get("seqdb")
            if not hmm:
                raise RuntimeError("hmmsearch 需要 --hmm（profile HMM 文件）")
            if not seqdb:
                raise RuntimeError("hmmsearch 需要 seqdb（官方位置参数 <seqdb>，目标序列库）")
            cmd = [binary, "--cpu", str(threads)]
            tblout = kw.get("tblout")
            if tblout:
                cmd += ["--tblout", str(tblout)]
            output = kw.get("output")
            if output:
                cmd += ["-o", str(output)]
            evalue = kw.get("evalue")
            if evalue is not None:
                cmd += ["-E", str(evalue)]
            # 官方用法：hmmsearch [options] <hmmfile> <seqdb>
            cmd += [str(hmm), str(seqdb)]

        return cmd

    def _build_v2(self, subcommand: str, **kw) -> list[str]:
        """HMMER 2.x 遗留版（bioconda 二进制带 2 后缀）命令行构建。"""
        if subcommand == "hmmbuild2":
            binary = self._resolve_tool_v2("hmmbuild")
            hmm_out = kw.get("hmm_out")
            msa = kw.get("msa")
            if not hmm_out:
                raise RuntimeError("hmmbuild2 需要 hmm_out（官方位置参数 <hmmfile>，如 family2.hmm）")
            if not msa:
                raise RuntimeError("hmmbuild2 需要 msa（官方位置参数 <alignfile>，多序列比对文件）")
            cmd: list[str] = [binary]
            name = kw.get("name")
            if name:
                cmd += ["-n", str(name)]
            if kw.get("force"):
                cmd += ["-F"]
            # HMMER2 hmmbuild 无线程参数（--threads 仅协议位，不注入）
            # 官方用法：hmmbuild [options] <hmmfile> <alignfile>
            cmd += [str(hmm_out), str(msa)]

        else:  # hmmsearch2
            binary = self._resolve_tool_v2("hmmsearch")
            hmm = kw.get("hmm")
            seqdb = kw.get("seqdb")
            if not hmm:
                raise RuntimeError("hmmsearch2 需要 hmm（官方位置参数 <hmmfile>，profile HMM 文件）")
            if not seqdb:
                raise RuntimeError("hmmsearch2 需要 seqdb（官方位置参数 <seqfile>，目标序列库）")
            threads = self._effective_threads(subcommand, kw.get("threads"))
            cmd = [binary, "--cpu", str(threads)]
            if kw.get("evalue") is not None:
                cmd += ["-E", str(kw["evalue"])]
            if kw.get("bit_score") is not None:
                cmd += ["-T", str(kw["bit_score"])]
            if kw.get("alignment") is not None:
                cmd += ["-A", str(kw["alignment"])]
            # 官方用法：hmmsearch [options] <hmmfile> <seqfile>
            cmd += [str(hmm), str(seqdb)]

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser, *, threads_help: str) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help=threads_help)
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")
    p.add_argument("--extra-args", dest="extra_args", help="透传给底层命令的额外参数（高级用法，慎用）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hmmer-skill",
        description="hmmer native 技能驱动（HMMER 3.x + HMMER 2.x 遗留版；profile HMM 建库与检索）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # ---------------- HMMER 3.x ----------------
    # hmmbuild <hmmfile_out> <msafile>
    pb = sub.add_parser("hmmbuild", help=SUBCOMMANDS["hmmbuild"])
    pb.add_argument("hmm_out", help="输出 HMM 文件（官方位置参数 <hmmfile_out>）")
    pb.add_argument("msa", help="输入多序列比对 MSA（官方位置参数 <msafile>，Stockholm/afa 等）")
    pb.add_argument("-n", "--name", help="给 HMM 命名（-n <s>；缺省取 MSA 名）")
    pb.add_argument("-o", "--output", help="汇总结构输出文件（-o <f>；缺省 stdout）")
    _add_runtime_opts(pb, threads_help="覆盖默认线程数（注入为 --cpu N）")

    # hmmpress <hmmfile>
    pp = sub.add_parser("hmmpress", help=SUBCOMMANDS["hmmpress"])
    pp.add_argument("hmm", help="待按压的 HMM 文件（官方位置参数 <hmmfile>）")
    pp.add_argument("-f", "--force", action="store_true", help="强制覆盖已存在的按压索引（-f）")
    _add_runtime_opts(pp, threads_help="覆盖默认线程数（hmmpress 无并行，仅接口一致）")

    # hmmsearch [options] <hmmfile> <seqdb>
    ps = sub.add_parser("hmmsearch", help=SUBCOMMANDS["hmmsearch"])
    ps.add_argument("--hmm", required=True, help="profile HMM 文件（官方位置参数 <hmmfile>）")
    ps.add_argument("seqdb", help="目标序列库（官方位置参数 <seqdb>，蛋白 FASTA）")
    ps.add_argument("--tblout", help="表格输出文件（--tblout <f>，每命中一行）")
    ps.add_argument("-E", "--evalue", type=float, help="报告序列的 E-value 阈值（默认 10.0）")
    ps.add_argument("-o", "--output", help="主输出文件（缺省 stdout）")
    _add_runtime_opts(ps, threads_help="覆盖默认线程数（注入为 --cpu N）")

    # ---------------- HMMER 2.x 遗留版 ----------------
    # hmmbuild2 <hmmfile> <alignfile>
    p2b = sub.add_parser("hmmbuild2", help=SUBCOMMANDS["hmmbuild2"])
    p2b.add_argument("hmm_out", help="输出 HMM 文件（官方位置参数 <hmmfile>）")
    p2b.add_argument("msa", help="输入多序列比对 MSA（官方位置参数 <alignfile>，Stockholm/SELEX/afa 等）")
    p2b.add_argument("-n", "--name", help="给 HMM 命名（-n <s>；缺省取 MSA 名）")
    p2b.add_argument("-F", "--force", action="store_true", help="强制覆盖已存在的 HMM 文件（-F）")
    _add_runtime_opts(p2b, threads_help="覆盖默认线程数（HMMER2 hmmbuild 无并行，仅接口一致、不注入）")

    # hmmsearch2 [options] <hmmfile> <seqfile>
    p2s = sub.add_parser("hmmsearch2", help=SUBCOMMANDS["hmmsearch2"])
    p2s.add_argument("hmm", help="profile HMM 文件（官方位置参数 <hmmfile>）")
    p2s.add_argument("seqdb", help="目标序列库（官方位置参数 <seqfile>，蛋白序列 FASTA 等）")
    p2s.add_argument("-E", "--evalue", type=float, help="序列 E-value 阈值（-E <x>；HMMER2 默认 10.0）")
    p2s.add_argument("-T", "--bit-score", dest="bit_score", type=float, help="序列位分阈值（-T <x>；默认负无穷）")
    p2s.add_argument("-A", "--alignment", type=int, help="比对输出的最优结构域条数（-A <n>；-A0 关闭）")
    _add_runtime_opts(p2s, threads_help="覆盖默认线程数（注入为 --cpu N）")

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = HmmerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = HmmerSkill()
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

    # 非捕获类（无 stdout）的子命令直接继承退出码
    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        # hmmbuild/hmmpress 无 -o 时汇总走 stdout 直接打印
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
