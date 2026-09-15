#!/usr/bin/env python3
"""fusionmap native 标准入口驱动（FusionMap — 融合基因检测）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py detect --input reads.fastq --ref /path/Data/Ref --output ./ --thread 8
   python main.py detect --input reads_1.fastq reads_2.fastq --ref Data/Ref --output out/ --thread 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐教学文档 12.1 / 3.14.1 FusionMap 示例）：
  FusionMap --fusion DetectFusion --input <fastq...> --ref <Ref_dir> --output <out_dir> --thread N
  Windows 版为 FusionMap.exe（Linux 下用 `mono FusionMap.exe ...` 运行）；官方另有 Linux 直接
  可执行的构建，驱动按可执行文件后缀自动选择是否前置 mono。

⚠️ 商业/许可受限：FusionMap 官方声明 free for noncommercial use（非商业免费），商业用途需向
   OmicSoft（omicsoft.com）获取授权；本驱动仅做命令编排，不随仓库分发软件本体。
"""

from __future__ import annotations

import argparse
import json
import os
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
    "detect": "FusionMap 融合检测（官方 --fusion DetectFusion --input <fastq...> --ref <Ref> --output <dir> --thread N）",
}

# 候选可执行文件名（Linux 直接可执行优先，其次 Windows .exe → 需 mono）
CANDIDATE_BINARIES = ("FusionMap", "FusionMap.exe")


class FusionMapSkill(base.SkillBase):
    software = "fusionmap"
    binary = "FusionMap"

    def _resolve_binary(self) -> str:
        """解析 FusionMap 可执行文件（惰性解析，测试可 monkeypatch）。

        优先 $FUSIONMAP_BIN 覆盖；否则在 PATH 中依次查找 FusionMap（Linux 直接可执行）与
        FusionMap.exe（Windows 版，需 mono）。返回实际路径。
        """
        override = os.environ.get("FUSIONMAP_BIN")
        if override:
            if not Path(override).exists():
                raise RuntimeError(f"$FUSIONMAP_BIN 指向的文件不存在: {override}")
            return override
        for name in CANDIDATE_BINARIES:
            path = base.which(name)
            if path:
                return path
        raise RuntimeError(
            "未找到 FusionMap / FusionMap.exe；请先从官方下载页 https://www.omicsoft.com/download/fusionmap/ "
            "获取预编译包（需接受许可），再用 native/install.sh 或 native/Dockerfile / Apptainer.def 部署"
            "（非商业用途；商业用途需授权）。"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 FusionMap 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

        binary = self._resolve_binary()
        inputs = kw.get("input")
        if inputs is None:
            raise ValueError("detect 缺少必填参数 input（--input，至少一个 FASTQ）")
        if isinstance(inputs, (list, tuple)):
            inputs = [str(i) for i in inputs]
        else:
            inputs = [str(inputs)]
        ref = kw.get("ref")
        out = kw.get("output")
        if not ref:
            raise ValueError("detect 缺少必填参数 ref（--ref 参考数据目录）")
        if not out:
            raise ValueError("detect 缺少必填参数 output（--output 输出目录）")

        threads = self._effective_threads(subcommand, kw.get("threads"))

        # Windows .exe 版需 mono 前缀；Linux 直接可执行构建直接调用
        cmd: list[str] = []
        if str(binary).endswith(".exe"):
            cmd += ["mono", str(binary)]
        else:
            cmd.append(str(binary))

        cmd += [
            "--fusion", str(kw.get("fusion") or "DetectFusion"),
            "--input", *inputs,
            "--ref", str(ref),
            "--output", str(out),
            "--thread", str(threads),
        ]

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
    p.add_argument("--threads", type=int, help="覆盖默认线程数（映射到 FusionMap --thread）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fusionmap-skill",
        description="fusionmap native 技能驱动（FusionMap 融合检测；自动线程注入）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pd = sub.add_parser("detect", help=SUBCOMMANDS["detect"])
    pd.add_argument("--input", nargs="+", required=True, help="输入 FASTQ（单端一个 / 双端两个，可多个）")
    pd.add_argument("--ref", required=True, help="参考数据目录（--ref）")
    pd.add_argument("--output", required=True, help="输出目录（--output）")
    pd.add_argument("--fusion", default="DetectFusion", help="操作模式（--fusion，默认 DetectFusion）")
    pd.add_argument("--extra-args", help="透传给 FusionMap 的额外参数（慎用）")
    _add_runtime_opts(pd)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = FusionMapSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = FusionMapSkill()
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
