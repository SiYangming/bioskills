#!/usr/bin/env python3
"""primer3（primer3_core）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   # 方式 A：喂入 primer3 设置文本文件（教学 p3_settings_file 即此类；TAG=VALUE，'=' 结尾）
   python main.py design p3_settings_file -o primer3.out
   python main.py design --input p3_settings_file > primer3.out      # 同上（stdout）
   # 方式 B：便捷参数（无 settings 文件时由驱动组装最小 settings）
   python main.py design --template ATGC... --id CL1 \
       --product-min 100 --product-max 300 -o primer3.out
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

等价于教学命令 primer3_core < p3_settings_file > primer3.out：settings 文本经 stdin 喂给
primer3_core，结果取 stdout（-o/--output 由驱动写文件）。所有子命令支持 --threads / --tmpdir
运行期覆盖（primer3_core 为单线程程序，线程参数仅作协议位，不强加/不注入）。

与 misa_primer3.pl 教学链路的关系：MISA（misa.pl）检测 SSR 后，misa_primer3.pl 对每个 SSR
位点生成含 SEQUENCE_ID/SEQUENCE_TEMPLATE 的 p3_settings_file 并调用 primer3_core 批量设计
侧翼引物；本驱动方式 A 可直接复喂该 settings 文件，方式 B 用 --template/--id/--product-* 组装
同一格式的最小 settings（SEQUENCE_ID/SEQUENCE_TEMPLATE/PRIMER_TASK=generic/
PRIMER_PRODUCT_SIZE_RANGE/=），适合无 MISA 环境的独立/教学用例。
"""
from __future__ import annotations

import argparse
import json
import os
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
    "design": "包装 primer3_core：Primer3 设置文本（settings 文件或 --template 便捷组装）→ 引物设计结果（stdout/-o）",
}

# 便捷模式默认 SEQUENCE_ID / 产物大小（--template 未给 --id / --product-* 时使用）
DEFAULT_SEQ_ID = "seq"
DEFAULT_PRODUCT_MIN = 100
DEFAULT_PRODUCT_MAX = 300

# 便捷模式最小 settings 尾部（= 为 primer3 输入块结束标记；与官方示例 / misa settings 一致）
_MINIMAL_SETTINGS_TAIL = "="


class Primer3Skill(base.SkillBase):
    software = "primer3"
    binary = "primer3_core"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/primer3/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """解析 primer3_core 可执行文件，带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda primer3 / quay.io/biocontainers/primer3，见 README「环境安装」）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 primer3_core 命令行（settings 文本由 prepare_settings 组装）。"""
        if subcommand != "design":
            raise RuntimeError(f"未知子命令: {subcommand}")
        binary = self._resolve_tool("primer3_core")

        # settings 来源互斥校验（放 build_command 前，确保任何运行路径都先报错）
        settings_file = kw.get("settings_file")
        template = kw.get("template")
        if settings_file and template:
            raise RuntimeError("settings_file（--input）与 --template 二选一，不能同时提供")

        cmd: list[str] = [binary]
        # 高级透传（慎用）：如 --strict_tags / --io_version=4 / --format_output
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def prepare_settings(self, **kw) -> str:
        """组装喂给 primer3_core 的完整设置文本（stdin 输入）。

        方式 A：原样读入 settings 文件（教学 p3_settings_file / MISA 生成物，TAG=VALUE，'=' 结尾；
          为兼容多块 settings 不擅自补 '='，按文件原样透传）。
        方式 B：--template 便捷模式——组装最小 settings：
          SEQUENCE_ID=<id> / SEQUENCE_TEMPLATE=<seq> / PRIMER_TASK=generic /
          PRIMER_PRODUCT_SIZE_RANGE=<min>-<max> / =
        """
        settings_file = kw.get("settings_file")
        template = kw.get("template")
        if settings_file:
            path = Path(settings_file)
            if not path.is_file():
                raise RuntimeError(f"settings 文件不存在: {path}")
            text = path.read_text(encoding="utf-8")
            if not text.strip():
                raise RuntimeError(f"settings 文件为空: {path}")
            return text
        if template:
            seq = "".join(str(template).split()).upper()  # 去内部空白并转大写（DNA/IUPAC）
            if not seq:
                raise RuntimeError("--template 序列为空")
            seq_id = str(kw.get("seq_id") or DEFAULT_SEQ_ID).strip()
            try:
                pmin = int(kw.get("product_min") or DEFAULT_PRODUCT_MIN)
                pmax = int(kw.get("product_max") or DEFAULT_PRODUCT_MAX)
            except (TypeError, ValueError) as exc:
                raise RuntimeError("--product-min/--product-max 需为整数") from exc
            if pmin <= 0 or pmax <= 0 or pmin > pmax:
                raise RuntimeError(f"产物大小范围非法: {pmin}-{pmax}（需 0 < min <= max）")
            lines = [
                f"SEQUENCE_ID={seq_id}",
                f"SEQUENCE_TEMPLATE={seq}",
                "PRIMER_TASK=generic",
                f"PRIMER_PRODUCT_SIZE_RANGE={pmin}-{pmax}",
                _MINIMAL_SETTINGS_TAIL,
            ]
            return "\n".join(lines) + "\n"
        raise RuntimeError(
            "design 需要 settings 来源：settings_file（positional / --input）或 --template 便捷参数"
        )

    def run(self, subcommand: str, **kwargs) -> base.RunResult:
        """构建命令、组装 settings 并经 stdin 喂给 primer3_core（等价 primer3_core < settings）。"""
        args = self.build_command(subcommand, **kwargs)
        settings_text = self.prepare_settings(**kwargs)
        run_env = os.environ.copy()
        run_env.update(self.env_vars)
        try:
            proc = subprocess.run(
                args,
                input=settings_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=run_env,
                check=False,
            )
        except FileNotFoundError as exc:
            raise RuntimeError(f"可执行文件未找到: {args[0]}") from exc
        result = base.RunResult(
            command=args, returncode=proc.returncode,
            stdout=proc.stdout or "", stderr=proc.stderr or "",
        )
        if not result.ok:
            raise RuntimeError(
                f"命令执行失败 (code={result.returncode}): {' '.join(args)}\n"
                f"stderr:\n{result.stderr}"
            )
        return result


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="primer3-skill",
        description="primer3（primer3_core）native 技能驱动（Primer3 设置文本 → PCR/SSR 引物设计）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # design: primer3_core < settings（文件或便捷组装）> stdout / -o
    pd = sub.add_parser("design", help=SUBCOMMANDS["design"])
    pd.add_argument("settings_file", nargs="?", help="Primer3 设置文本路径（TAG=VALUE，'=' 结尾；等价 --input）")
    pd.add_argument("--input", dest="settings_file", help="同上：settings 文件路径（与 positional 二选一）")
    pd.add_argument("-o", "--output", help="设计结果输出文件（默认 stdout；驱动写捕获的 stdout）")
    pd.add_argument("--template", help="便捷模式：SEQUENCE_TEMPLATE 模板序列（与 settings 文件互斥）")
    pd.add_argument("--id", dest="seq_id", help=f"便捷模式：SEQUENCE_ID（默认 {DEFAULT_SEQ_ID}）")
    pd.add_argument("--product-min", type=int, default=DEFAULT_PRODUCT_MIN,
                    help=f"便捷模式：产物大小下限（默认 {DEFAULT_PRODUCT_MIN}）")
    pd.add_argument("--product-max", type=int, default=DEFAULT_PRODUCT_MAX,
                    help=f"便捷模式：产物大小上限（默认 {DEFAULT_PRODUCT_MAX}）")
    pd.add_argument("--extra-args", dest="extra_args",
                    help="透传给 primer3_core 的额外参数（如 --strict_tags --io_version=4，高级用法，慎用）")
    _add_runtime_opts(pd)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（协议位：primer3_core 单线程，不强加）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Primer3Skill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Primer3Skill()
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

    # design 结果（primer3_core stdout）：-o 写文件，否则直通 stdout
    out_text = result.stdout
    out_path = kw.get("output")
    if out_path:
        Path(out_path).write_text(out_text, encoding="utf-8")
    else:
        sys.stdout.write(out_text)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
