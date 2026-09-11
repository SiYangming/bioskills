#!/usr/bin/env python3
"""MUSCLE native 标准入口驱动（多序列比对）。

MUSCLE 有两条互不兼容的命令行代际，本驱动做「版本探测 + 双 CLI 适配」：
- v3（3.8.x，教学课件常用 3.8.31、bioconda 亦提供 3.8.1551）：``muscle -in <fa> -out <aln>``
  （单线程；``muscle -in <fa>`` 不带 -out 时把比对写到 stdout）。
- v5（5.x，bioconda 现行 latest 5.3）：``muscle -align <fa> -output <aln> -threads N``
  （``-output`` 必填；另有 ``-super5`` 等子命令/模式）。

驱动先跑 ``muscle -version`` / ``muscle --version``，据输出判定 3.x / 5.x，再拼对应参数。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py align input.fa -o aligned.fa --threads 8     # 自动适配 v3/v5
   python main.py align input.fa --threads 8                    # 缺省 stdout（v5 驱动临时文件回显）
   python main.py align -i input.fa -o aligned.fa --threads 8   # -i/--input 与位置参数等价
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（v5）与临时目录（--tmpdir，同时设 TMPDIR）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
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
    "align": "muscle：多序列比对（FASTA → 等长比对 FASTA）；驱动自动适配 v3(-in/-out) 与 v5(-align/-output)",
}


class MuscleSkill(base.SkillBase):
    software = "muscle"
    binary = "muscle"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/muscle/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)
        self._version_cache: tuple[str, str] | None = None

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def detect_version(self) -> tuple[str, str]:
        """探测已安装 muscle 的主版本代际。

        返回 ``(major, raw)``：major ∈ {"3", "5"}；raw 为 ``muscle -version`` 的原始输出。
        - v3 输出形如 ``MUSCLE v3.8.1551 by Robert C. Edgar``
        - v5 输出形如 ``muscle 5.3.osxarm64 []``
        探测失败时回退为 v5（native 登记版本）并保留 raw=""。
        """
        if self._version_cache is not None:
            return self._version_cache

        binary = self._resolve_binary()
        raw = ""
        for flag in ("-version", "--version"):
            res = base.run_command([binary, flag], check=False)
            out = (res.stdout or "") + (res.stderr or "")
            if out.strip():
                raw = out.strip()
                break

        major = "5"
        if re.search(r"muscle\s+v?3\.", raw, re.IGNORECASE) or re.search(r"\bv?3\.\d+\.\d+", raw):
            major = "3"
        elif re.search(r"\b5\.\d", raw):
            major = "5"

        self._version_cache = (major, raw)
        return self._version_cache

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数、结合探测到的版本构建 muscle 命令行。"""
        if subcommand != "align":
            raise RuntimeError(f"未知子命令: {subcommand}")

        inp = kw.get("input")
        if not inp:
            raise RuntimeError("align 需要 input（输入 FASTA，位置参数或 -i/--input）")

        binary = self._resolve_binary()
        major, _ = self.detect_version()
        output = kw.get("output")

        if major == "3":
            # v3：muscle -in <fa> [-out <aln>]（单线程，无 -threads；缺 -out 时比对写 stdout）
            cmd: list[str] = [binary, "-in", str(inp)]
            if output:
                cmd += ["-out", str(output)]
        else:
            # v5：muscle -align <fa> -output <aln> -threads N（-output 必填）
            threads = self._effective_threads("align", kw.get("threads"))
            cmd = [binary, "-align", str(inp)]
            if output:
                cmd += ["-output", str(output)]
            cmd += ["-threads", str(threads)]

        # 高级透传（慎用；v5 的 -super5 等模式选项会替换 -align 语义）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="muscle-skill",
        description="MUSCLE native 技能驱动（多序列比对；自动适配 v3/v5 CLI 与线程/临时目录）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # align: auto-adapt v3 (-in/-out) | v5 (-align/-output/-threads)
    pa = sub.add_parser("align", help=SUBCOMMANDS["align"])
    pa.add_argument("input", nargs="?", help="输入序列 FASTA（多序列核酸/氨基酸；位置参数或 -i/--input）")
    pa.add_argument("-i", "--input", dest="input_opt", help="输入序列 FASTA（与位置参数等价）")
    pa.add_argument("--in", "--align", dest="input_alias",
                    help="输入序列 FASTA（对齐 MUSCLE 原生 v3 -in / v5 -align 命名，等价 -i）")
    pa.add_argument("-o", "--output", "--out", dest="output",
                    help="比对结果输出文件（驱动映射 v3 -out / v5 -output；缺省 stdout）")
    pa.add_argument("--extra-args", dest="extra_args", help="透传给 muscle 的额外参数（高级用法，慎用）")
    _add_runtime_opts(pa)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅 v5 注入 -threads N）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def _pick_input(ns: argparse.Namespace) -> str | None:
    """位置参数优先，其次 -i/--input，再次 --in/--align。"""
    return ns.input or ns.input_opt or ns.input_alias


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = MuscleSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MuscleSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    output = getattr(ns, "output", None)
    # 统一 stdout 语义：v3 可省 -out 直接写 stdout，v5 的 -output 必填；
    # 未给 -o 时用临时文件承接对齐结果，运行后回显 stdout 并清理。
    tmp_dir: str | None = None
    if not output:
        Path(skill.tmpdir).mkdir(parents=True, exist_ok=True)
        tmp_dir = tempfile.mkdtemp(prefix="muscle_", dir=skill.tmpdir)
        output = os.path.join(tmp_dir, "alignment.fa")

    kw: dict = {"input": _pick_input(ns), "output": output, "threads": ns.threads}
    if ns.extra_args:
        kw["extra_args"] = ns.extra_args

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        if tmp_dir:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stderr:
        sys.stderr.write(result.stderr)
    # 对齐结果：写到文件（-o）或回显 stdout（缺省临时文件）
    if tmp_dir:
        out_path = Path(output)
        if out_path.exists():
            sys.stdout.write(out_path.read_text())
        shutil.rmtree(tmp_dir, ignore_errors=True)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
