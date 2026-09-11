#!/usr/bin/env python3
"""hmmer（HMMER 3.x）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py hmmbuild family.hmm family.sto --threads 4
   python main.py hmmpress family.hmm
   python main.py hmmsearch --hmm family.hmm proteins.fa --tblout hits.tbl -E 10 --threads 4
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（--threads → HMMER 的 --cpu N）与临时目录（--tmpdir → TMPDIR）。

HMMER 3.x 官方 CLI 语义（本驱动对齐）：
- hmmbuild <hmmfile_out> <msafile>：由多序列比对训练 profile HMM（-n 命名、-o 汇总输出）
- hmmpress <hmmfile>：把 HMM 库按压为 <hmm>.h3f/.h3i/.h3m/.h3p（-f 强制覆盖；无并行）
- hmmsearch [options] <hmmfile> <seqdb>：用 HMM 检索序列库（--tblout 表格、-o 主输出、-E 阈值）

本驱动为软件模块 modules/hmmer/ 的 HMMER 3.x 现行实现（native/）；HMMER 2.x 遗留版见同模块
native2/（README「HMMER 2.x 遗留版（native2 实现）」章节）。
"""
from __future__ import annotations

import argparse
import json
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
    "hmmbuild": "hmmbuild：由多序列比对（MSA）训练 profile HMM（官方 <hmmfile_out> <msafile>）",
    "hmmpress": "hmmpress：把 HMM 库按压为 .h3f/.h3i/.h3m/.h3p 索引（供 hmmscan 快速检索）",
    "hmmsearch": "hmmsearch：用 profile HMM 检索蛋白序列库（--tblout 表格、-o 主输出缺省 stdout）",
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

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（hmmbuild/hmmpress/hmmsearch），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda hmmer=3.4 / 官方 release 源码归档提供 hmmbuild/hmmpress/hmmsearch 等）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 HMMER 3.x 命令行。"""
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

        elif subcommand == "hmmsearch":
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
        prog="hmmer-skill",
        description="hmmer（HMMER 3.x）native 技能驱动（自动线程/临时目录优化；profile HMM 建库与检索）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # hmmbuild <hmmfile_out> <msafile>
    pb = sub.add_parser("hmmbuild", help=SUBCOMMANDS["hmmbuild"])
    pb.add_argument("hmm_out", help="输出 HMM 文件（官方位置参数 <hmmfile_out>）")
    pb.add_argument("msa", help="输入多序列比对 MSA（官方位置参数 <msafile>，Stockholm/afa 等）")
    pb.add_argument("-n", "--name", help="给 HMM 命名（-n <s>；缺省取 MSA 名）")
    pb.add_argument("-o", "--output", help="汇总结构输出文件（-o <f>；缺省 stdout）")
    pb.add_argument("--extra-args", dest="extra_args", help="透传给 hmmbuild 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pb)

    # hmmpress <hmmfile>
    pp = sub.add_parser("hmmpress", help=SUBCOMMANDS["hmmpress"])
    pp.add_argument("hmm", help="待按压的 HMM 文件（官方位置参数 <hmmfile>）")
    pp.add_argument("-f", "--force", action="store_true", help="强制覆盖已存在的按压索引（-f）")
    pp.add_argument("--extra-args", dest="extra_args", help="透传给 hmmpress 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pp)

    # hmmsearch [options] <hmmfile> <seqdb>
    ps = sub.add_parser("hmmsearch", help=SUBCOMMANDS["hmmsearch"])
    ps.add_argument("--hmm", required=True, help="profile HMM 文件（官方位置参数 <hmmfile>）")
    ps.add_argument("seqdb", help="目标序列库（官方位置参数 <seqdb>，蛋白 FASTA）")
    ps.add_argument("--tblout", help="表格输出文件（--tblout <f>，每命中一行）")
    ps.add_argument("-E", "--evalue", type=float, help="报告序列的 E-value 阈值（默认 10.0）")
    ps.add_argument("-o", "--output", help="主输出文件（缺省 stdout）")
    ps.add_argument("--extra-args", dest="extra_args", help="透传给 hmmsearch 的额外参数（高级用法，慎用）")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（注入为 --cpu N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


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
