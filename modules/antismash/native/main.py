#!/usr/bin/env python3
"""antismash native 标准入口驱动（次级代谢产物 BGC 预测）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py download_db --output-dir ~/antismash_db            # 下载数据库（数 GB，先跑）
   python main.py run genome.gbk --taxon bacteria --cpus 8 --output-dir asm_out
   python main.py run genome.gbk --taxon fungi -c 8                  # 真菌教学典型用法
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令自动注入线程（--threads/--cpus）与临时目录（--tmpdir，同时设 TMPDIR）；
每个子命令还支持 --dry-run（打印将执行的命令行后退出，不真正运行）。

CLI 事实（按登记的 antismash=8.0.4 / 兼容 7.1.0，源码在线核实）：
- 输出目录参数 v7 起为 --output-dir（v6 及更早为 --outputfolder，驱动不针对旧版）；
- --taxon 取值 bacteria|fungi（默认 bacteria），-c/--cpus 并行数，--databases PATH 指定库目录；
- 数据库下载器 download-antismash-databases 的目录参数为 --database-dir（7.x/8.x 一致）；
- 首次使用必须下载数据库（Pfam/Resfam/ClusterBlast/MiBIG 等，~15GB 磁盘）；本模块测试
  绝不在测试内真跑 run/download_db（见 test/run_test.sh）。
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
    "run": "antismash：输入基因组（GBK/EMBL/FASTA）→ 次级代谢 BGC 预测与注释"
           "（HTML 报告 + region GenBank/JSON；需先下载数据库）",
    "download_db": "download-antismash-databases：下载并预处理 antismash 运行数据库"
                   "（Pfam/Resfam/ClusterBlast/MiBIG 等，数 GB，首次运行前必做）",
}

# 数据库下载器入口名（随 bioconda 包装入，与 antismash 同目录）
DATABASE_TOOL = "download-antismash-databases"


class AntismashSkill(base.SkillBase):
    software = "antismash"
    binary = "antismash"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/antismash/meta.yaml（不在 native/ 下），
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
        """返回可执行文件路径；未安装时退回命令名。

        --dry-run / 命令行构造断言（test/run_test.sh）在无二进制机器上也应可跑，
        因此这里不抛错；真跑时由 base.run_command 在 FileNotFoundError 上给出清晰报错。
        """
        return shutil.which(tool) or tool

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 antismash 命令行（不执行）。"""
        if subcommand == "run":
            return self._build_run(kw)
        if subcommand == "download_db":
            return self._build_download_db(kw)
        raise RuntimeError(f"未知子命令: {subcommand}")

    # -- run: antismash [options] <input.gbk> ------------------------------ #
    def _build_run(self, kw: dict) -> list[str]:
        input_gbk = kw.get("input_gbk")
        if not input_gbk:
            raise RuntimeError("run 需要 input_gbk（输入基因组 GBK/EMBL/FASTA，位置参数）")
        cpus = kw.get("cpus") or self._effective_threads("run", kw.get("threads"))
        taxon = str(kw.get("taxon") or "bacteria")
        if taxon not in ("bacteria", "fungi"):
            raise RuntimeError(
                f"未知 --taxon '{taxon}'（antismash v7+ 取值 bacteria|fungi，默认 bacteria）"
            )

        cmd: list[str] = [self._resolve_tool(self.binary)]
        cmd += ["--cpus", str(cpus), "--taxon", taxon]

        output_dir = kw.get("output_dir")
        if output_dir:
            cmd += ["--output-dir", str(output_dir)]

        genefinding_tool = kw.get("genefinding_tool")
        if genefinding_tool:
            cmd += ["--genefinding-tool", str(genefinding_tool)]

        cmd.append(str(input_gbk))
        return self._append_extra(cmd, kw)

    # -- download_db: download-antismash-databases [--database-dir PATH] --- #
    def _build_download_db(self, kw: dict) -> list[str]:
        cmd: list[str] = [self._resolve_tool(DATABASE_TOOL)]
        output_dir = kw.get("output_dir")
        if output_dir:
            # 7.x/8.x 下载器目录参数为 --database-dir（源码在线核实；v6 及更早无此参数）
            cmd += ["--database-dir", str(output_dir)]
        return self._append_extra(cmd, kw)

    @staticmethod
    def _append_extra(cmd: list[str], kw: dict) -> list[str]:
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="antismash-skill",
        description="antismash native 技能驱动（自动线程/内存/IO 优化；次级代谢 BGC 预测）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # run: antismash --cpus N --taxon {bacteria,fungi} [--output-dir DIR]
    #                [--genefinding-tool T] <input.gbk>
    pr = sub.add_parser("run", help=SUBCOMMANDS["run"])
    pr.add_argument("input_gbk", help="输入基因组序列文件（GenBank .gbk/.gbff；也接受 EMBL/FASTA）")
    pr.add_argument("-c", "--cpus", type=int, help="并行 CPU 数（等价 antismash --cpus；默认 8）")
    pr.add_argument(
        "--taxon", choices=("bacteria", "fungi"), default="bacteria",
        help="输入物种分类（antismash v7+ 取值 bacteria|fungi；教学真菌示例用 fungi）",
    )
    pr.add_argument(
        "--output-dir", dest="output_dir",
        help="结果输出目录（antismash v7+ 参数 --output-dir；v6 及更早为 --outputfolder）",
    )
    pr.add_argument(
        "--genefinding-tool", dest="genefinding_tool",
        help="基因预测工具覆盖（如 prodigal/glimmerhmm/none；缺省按 --taxon 智能选择）",
    )
    pr.add_argument("--extra-args", dest="extra_args",
                    help="透传给 antismash 的额外参数（如 --databases PATH --minimal，高级用法，慎用）")
    pr.add_argument("--dry-run", action="store_true", help="仅打印将执行的命令行，不真正运行")
    _add_runtime_opts(pr)

    # download_db: download-antismash-databases [--database-dir DIR]
    pd = sub.add_parser("download_db", help=SUBCOMMANDS["download_db"])
    pd.add_argument(
        "--output-dir", dest="output_dir",
        help="数据库安装目录（映射为 download-antismash-databases 的 --database-dir，7.x/8.x；"
             "缺省为 antismash 包内默认库目录）",
    )
    pd.add_argument("--extra-args", dest="extra_args",
                    help="透传给 download-antismash-databases 的额外参数（高级用法，慎用）")
    pd.add_argument("--dry-run", action="store_true", help="仅打印将执行的命令行，不真正运行")
    _add_runtime_opts(pd)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（run 时等价 --cpus）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = AntismashSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AntismashSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "dry_run") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if ns.dry_run:
        # 构造断言 / 调试：只打印命令行（JSON 数组），不执行
        print(json.dumps(cmd, ensure_ascii=False))
        return 0

    result = skill.run(ns.subcommand, **kw)
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
