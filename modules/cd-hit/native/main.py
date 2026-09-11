#!/usr/bin/env python3
"""cd-hit native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py protein -i proteins.fa -o nr.fa -c 0.9 --threads 8
   python main.py est     -i transcripts.fa -o nr.fa -c 0.95 --threads 8 --memory 4000
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（-T）与临时目录（TMPDIR）。

两个子命令分别包装 CD-HIT 的两个入口二进制：
- protein = cd-hit      蛋白序列去冗余/聚类
- est     = cd-hit-est  核酸（EST/转录组）序列去冗余/聚类
两者参数语义一致：-i 输入、-o 输出代表序列（同时写 <output>.clstr）、-c 相似度阈值、
-T 线程、-M 内存上限（MB，0 为不限制）。
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
    "protein": "cd-hit：蛋白序列按相似度阈值聚类去冗余（代表序列 + .clstr）",
    "est": "cd-hit-est：核酸（EST/转录组）序列按相似度阈值聚类去冗余（代表序列 + .clstr）",
}

# 子命令 → 上游二进制
_SUBCOMMAND_BINARY = {
    "protein": "cd-hit",
    "est": "cd-hit-est",
}


class CdHitSkill(base.SkillBase):
    software = "cd-hit"
    binary = "cd-hit"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/cd-hit/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_tool(self, tool: str) -> str:
        """解析配套可执行文件（如 cd-hit-est），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda cd-hit 会同时提供 cd-hit / cd-hit-est / cd-hit-2d / cd-hit-est-2d 等）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 cd-hit / cd-hit-est 命令行。"""
        if subcommand not in _SUBCOMMAND_BINARY:
            raise RuntimeError(f"未知子命令: {subcommand}")

        binary = self._resolve_tool(_SUBCOMMAND_BINARY[subcommand])
        input_fa = kw.get("input")
        if not input_fa:
            raise RuntimeError(f"{subcommand} 需要 -i/--input（输入 FASTA）")
        output = kw.get("output")
        if not output:
            raise RuntimeError(f"{subcommand} 需要 -o/--output（输出代表序列 FASTA 路径）")

        threads = self._effective_threads(subcommand, kw.get("threads"))
        identity = kw.get("identity", 0.9)

        cmd: list[str] = [
            binary,
            "-i", str(input_fa),
            "-o", str(output),
            "-c", str(identity),
            "-T", str(threads),
        ]

        # 可选内存上限（MB；0 = 不限制；缺省不注入则用 cd-hit 自身默认 800）
        memory = kw.get("memory")
        if memory is not None:
            cmd += ["-M", str(memory)]

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
        prog="cd-hit-skill",
        description="cd-hit native 技能驱动（自动线程/TMPDIR 优化；蛋白/核酸序列聚类去冗余）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # protein: cd-hit       -i <in.fa> -o <out.fa> -c <id> -T <n> [-M <mb>]
    pp = sub.add_parser("protein", help=SUBCOMMANDS["protein"])
    _add_common_opts(pp)

    # est: cd-hit-est       -i <in.fa> -o <out.fa> -c <id> -T <n> [-M <mb>]
    pe = sub.add_parser("est", help=SUBCOMMANDS["est"])
    _add_common_opts(pe)

    return p


def _add_common_opts(p: argparse.ArgumentParser) -> None:
    """两个子命令共用的输入/参数（含运行期覆盖项 --threads/--tmpdir）。"""
    p.add_argument("-i", "--input", required=True, help="输入 FASTA（可 .gz）")
    p.add_argument("-o", "--output", required=True,
                   help="输出代表序列 FASTA 路径（同时写 <output>.clstr）")
    p.add_argument("-c", "--identity", type=float, default=0.9,
                   help="相似度阈值 0.0-1.0（默认 0.9）")
    p.add_argument("-M", "--memory", type=int, default=None,
                   help="内存上限 MB（0 = 不限制；缺省用 cd-hit 默认 800）")
    p.add_argument("--extra-args", dest="extra_args",
                   help="透传给 cd-hit / cd-hit-est 的额外参数（高级用法，慎用）")
    p.add_argument("--threads", type=int, help="覆盖默认线程数（-T）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:10s} {v}")
        return 0
    if "--schema" in args:
        skill = CdHitSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = CdHitSkill()
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
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
