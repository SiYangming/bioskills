#!/usr/bin/env python3
"""go_class native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py config     go.obo
   python main.py annot2wego go.annot -o go.wego
   python main.py classify   go.obo go.wego -o go_class.tab
   python main.py svg        go.wego --outdir ./ --name out --color green \
       --mark "Whole Genome Genes" --note "GO Class of whole genome genes"
   python main.py distribute out.lst out.svg
   python main.py resize     out.svg 150 -100
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（对应 13.md「九、GO功能分类（WEGO图）」）：
  config       make_go_class_config.pl <go.obo>
  annot2wego   annot2wego.pl <go.annot>                                   （写 stdout）
  classify     get_Genes_From_GO.pl <go.obo> <go.wego>                   （写 stdout）
  svg          go_svg.pl --outdir <d> --name <n> [--color] [--mark] [--note] <go.wego>
  distribute   distributing_svg.pl <out.lst> <out.svg>
  resize       changsvgsize.pl <out.svg> <width> <height>
注意：go_class 为 Perl 脚本集（无统一二进制），各子命令按名解析对应脚本（PATH 或 GO_CLASS_HOME/{bin,svg}）；
      --threads 仅作统一接口与上层调度参考，不注入命令行。
"""

from __future__ import annotations

import argparse
import json
import os
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
    "config": "初始化 GO 配置：make_go_class_config.pl <go.obo>",
    "annot2wego": "注释转 WEGO 格式：annot2wego.pl <go.annot>（写 stdout，可 -o 落盘）",
    "classify": "GO 分类统计：get_Genes_From_GO.pl <go.obo> <go.wego>（写 stdout，可 -o 落盘）",
    "svg": 'WEGO 图：go_svg.pl --outdir <d> --name <n> [--color] [--mark] [--note] <go.wego>',
    "distribute": "组合 SVG：distributing_svg.pl <out.lst> <out.svg>",
    "resize": "调整 SVG 尺寸：changsvgsize.pl <out.svg> <width> <height>",
}

# 子命令 -> 对应 go_class 脚本名（脚本在 PATH 或 $GO_CLASS_HOME/{bin,svg}）
SCRIPT_BY_SUBCOMMAND = {
    "config": "make_go_class_config.pl",
    "annot2wego": "annot2wego.pl",
    "classify": "get_Genes_From_GO.pl",
    "svg": "go_svg.pl",
    "distribute": "distributing_svg.pl",
    "resize": "changsvgsize.pl",
}

# 写 stdout 的子命令（main() 可用 -o 落盘）
STDOUT_SUBCOMMANDS = {"annot2wego", "classify"}


class GoClassSkill(base.SkillBase):
    software = "go_class"
    binary = "annot2wego.pl"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _resolve_script(self, script: str) -> str:
        """按名解析 go_class 脚本：优先 PATH，其次 $GO_CLASS_HOME/{bin,svg,}。"""
        found = base.which(script)
        if found:
            return found
        home = os.environ.get("GO_CLASS_HOME")
        if home:
            for cand in (Path(home) / "bin" / script,
                         Path(home) / "svg" / script,
                         Path(home) / script):
                if cand.is_file():
                    return str(cand)
        raise RuntimeError(
            f"未找到 go_class 脚本 '{script}'；请将其 bin/（及 svg/）加入 PATH，"
            f"或设置 GO_CLASS_HOME 指向 go_class 解压目录。"
        )

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建对应 go_class 脚本命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        script = self._resolve_script(SCRIPT_BY_SUBCOMMAND[subcommand])
        cmd: list[str] = [script]

        if subcommand == "config":
            obo = kw.get("obo") or kw.get("input")
            if not obo:
                raise ValueError("config 缺少必填参数 obo（go.obo）")
            cmd.append(str(obo))

        elif subcommand == "annot2wego":
            annot = kw.get("annot") or kw.get("input")
            if not annot:
                raise ValueError("annot2wego 缺少必填参数 annot（go.annot）")
            cmd.append(str(annot))

        elif subcommand == "classify":
            obo = kw.get("obo")
            wego = kw.get("wego")
            if not obo or not wego:
                raise ValueError("classify 缺少必填参数 obo/wego（go.obo + go.wego）")
            cmd += [str(obo), str(wego)]

        elif subcommand == "svg":
            wego = kw.get("wego") or kw.get("input")
            if not wego:
                raise ValueError("svg 缺少必填参数 wego（go.wego）")
            if kw.get("outdir"):
                cmd += ["--outdir", str(kw["outdir"])]
            if kw.get("name"):
                cmd += ["--name", str(kw["name"])]
            if kw.get("color"):
                cmd += ["--color", str(kw["color"])]
            if kw.get("mark"):
                cmd += ["--mark", str(kw["mark"])]
            if kw.get("note"):
                cmd += ["--note", str(kw["note"])]
            cmd.append(str(wego))

        elif subcommand == "distribute":
            lst, svg = kw.get("lst"), kw.get("svg")
            if not lst or not svg:
                raise ValueError("distribute 缺少必填参数 lst/svg（out.lst + out.svg）")
            cmd += [str(lst), str(svg)]

        elif subcommand == "resize":
            svg = kw.get("svg")
            if not svg or kw.get("width") is None or kw.get("height") is None:
                raise ValueError("resize 缺少必填参数 svg/width/height")
            cmd += [str(svg), str(kw["width"]), str(kw["height"])]

        # 线程：go_class 脚本单线程，仅解析优先级（统一接口），不注入
        self._effective_threads(subcommand, kw.get("threads"))

        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（stdout 子命令由 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（go_class 脚本单线程，仅调度参考）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="go_class-skill",
        description="go_class native 技能驱动（GO 功能分类 / WEGO 图；无官方渠道，需自备 tar 包）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pc = sub.add_parser("config", help=SUBCOMMANDS["config"])
    pc.add_argument("obo", help="GO 本体文件 go.obo")
    pc.add_argument("--extra-args", help="透传给 make_go_class_config.pl 的额外参数")
    _add_runtime_opts(pc)

    pa = sub.add_parser("annot2wego", help=SUBCOMMANDS["annot2wego"])
    pa.add_argument("annot", help="GO 注释文件 go.annot")
    pa.add_argument("-o", "--output", help="输出 go.wego 路径（默认写 stdout）")
    pa.add_argument("--extra-args", help="透传给 annot2wego.pl 的额外参数")
    _add_runtime_opts(pa)

    pk = sub.add_parser("classify", help=SUBCOMMANDS["classify"])
    pk.add_argument("obo", help="GO 本体文件 go.obo")
    pk.add_argument("wego", help="WEGO 格式文件 go.wego")
    pk.add_argument("-o", "--output", help="输出 go_class.tab 路径（默认写 stdout）")
    pk.add_argument("--extra-args", help="透传给 get_Genes_From_GO.pl 的额外参数")
    _add_runtime_opts(pk)

    ps = sub.add_parser("svg", help=SUBCOMMANDS["svg"])
    ps.add_argument("wego", help="WEGO 格式文件 go.wego")
    ps.add_argument("--outdir", default="./", help="输出目录（默认当前目录）")
    ps.add_argument("--name", default="out", help="输出名前缀（默认 out）")
    ps.add_argument("--color", help="配色（如 green）")
    ps.add_argument("--mark", help="图例标注（如 \"Whole Genome Genes\"）")
    ps.add_argument("--note", help="图注文本")
    ps.add_argument("--extra-args", help="透传给 go_svg.pl 的额外参数")
    _add_runtime_opts(ps)

    pd = sub.add_parser("distribute", help=SUBCOMMANDS["distribute"])
    pd.add_argument("lst", help="out.lst（go_svg.pl 产出）")
    pd.add_argument("svg", help="输出 SVG 路径")
    pd.add_argument("--extra-args", help="透传给 distributing_svg.pl 的额外参数")
    _add_runtime_opts(pd)

    pr = sub.add_parser("resize", help=SUBCOMMANDS["resize"])
    pr.add_argument("svg", help="待调整的 SVG 文件")
    pr.add_argument("width", help="目标宽度（如 150）")
    pr.add_argument("height", help="目标高度（如 -100）")
    pr.add_argument("--extra-args", help="透传给 changsvgsize.pl 的额外参数")
    _add_runtime_opts(pr)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GoClassSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GoClassSkill()
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

    # stdout 子命令：-o 指定时落盘，否则透传
    if ns.subcommand in STDOUT_SUBCOMMANDS and getattr(ns, "output", None) and result.stdout:
        with open(ns.output, "w", encoding="utf-8") as fh:
            fh.write(result.stdout)
    elif result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
