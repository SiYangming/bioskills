#!/usr/bin/env python3
"""soapfuse native 标准入口驱动（SOAPfuse — 融合基因检测）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py run -c config/config.txt -fd raw_data -l sample.list -o out_dir
   python main.py run -c config.txt -fd raw_data -l sample.list -o out_dir -fs 1 -es 9 --threads 8
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对齐官方 SOAPfuse wiki "Run SOAPfuse"，主脚本 SOAPfuse-RUN.pl 用 perl 运行）：
  perl SOAPfuse-RUN.pl -c <config_file> -fd <WHOLE_SEQ-DATA_DIR> -l <sample_list> -o <out_directory>
                       [-fs <start_step>] [-es <end_step>] [-tp <tmp_postfix>]
注意：v1.27 起部分功能打包为 SOAPfuse perl 模块，运行前须把模块目录加入 PERL5LIB（官方 wiki 说明）；
     SOAPfuse 无命令行线程参数（线程在 config.txt 内配置），--threads 仅为接口对齐而接受。
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
    "run": "SOAPfuse 融合检测主流程（perl SOAPfuse-RUN.pl -c <config> -fd <data_dir> -l <sample_list> -o <out_dir>）",
}


class SoapfuseSkill(base.SkillBase):
    software = "soapfuse"
    binary = "SOAPfuse-RUN.pl"

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 SOAPfuse 命令行（主脚本用 perl 运行）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")

        config = kw.get("config")
        data_dir = kw.get("data_dir")
        sample_list = kw.get("sample_list")
        out = kw.get("output")
        if not config:
            raise ValueError("run 缺少必填参数 config（-c 配置文件）")
        if not data_dir:
            raise ValueError("run 缺少必填参数 data_dir（-fd 双端数据目录）")
        if not sample_list:
            raise ValueError("run 缺少必填参数 sample_list（-l 样本列表文件）")
        if not out:
            raise ValueError("run 缺少必填参数 output（-o 输出目录）")

        script = self._resolve_binary()
        # 官方用法：perl SOAPfuse-RUN.pl ...
        cmd: list[str] = ["perl", script]
        cmd += ["-c", str(config)]
        cmd += ["-fd", str(data_dir)]
        cmd += ["-l", str(sample_list)]
        cmd += ["-o", str(out)]
        if kw.get("start_step") is not None:
            cmd += ["-fs", str(kw["start_step"])]
        if kw.get("end_step") is not None:
            cmd += ["-es", str(kw["end_step"])]
        if kw.get("tmp_postfix"):
            cmd += ["-tp", str(kw["tmp_postfix"])]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += shlex.split(str(extra))

        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。

    注意：SOAPfuse 无命令行线程参数（线程在 config.txt 内配置），--threads 仅为接口对齐而接受。
    """
    p.add_argument("--threads", type=int, help="覆盖默认线程数（SOAPfuse 线程在 config.txt 内配置，实际不生效）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="soapfuse-skill",
        description="soapfuse native 技能驱动（SOAPfuse 融合检测；主脚本 perl SOAPfuse-RUN.pl）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("-c", "--config", required=True, help="配置文件（-c）")
    pr.add_argument("-fd", "--data-dir", required=True, help="双端 reads 目录（-fd）")
    pr.add_argument("-l", "--sample-list", required=True, help="样本信息列表文件（-l）")
    pr.add_argument("-o", "--output", required=True, help="输出目录（-o）")
    pr.add_argument("-fs", "--start-step", type=int, default=1, help="起始步骤（-fs，默认 1）")
    pr.add_argument("-es", "--end-step", type=int, default=9, help="结束步骤（-es，默认 9）")
    pr.add_argument("-tp", "--tmp-postfix", help="临时目录名后缀（-tp）")
    pr.add_argument("--extra-args", help="透传给 SOAPfuse-RUN.pl 的额外参数（慎用）")
    _add_runtime_opts(pr)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = SoapfuseSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = SoapfuseSkill()
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
