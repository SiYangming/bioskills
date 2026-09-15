#!/usr/bin/env python3
"""usearch native 标准入口驱动（USEARCH 8.1.1861）。

⚠️ 许可提示：USEARCH 为 drive5 商业软件（学术免费但需注册下载、须遵守 USEARCH 许可）；
   本模块登记的 8.1.1861 历史二进制经 rcedgar/usearch_old_binaries 以 CC0-1.0 重发布，
   但 drive5 商业版仍为专有许可。请在商业使用前阅读并遵守上游许可（详见 README / meta.yaml）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py cluster_otus uniques.fa -o otus.fa --relabel OTU --threads 8
   python main.py uchime_denovo seqs.fa -o chimeras.uchime --chimeras chim.fa
   python main.py usearch_global seqs.fa -d ref.fa --id 0.97 --otutabout otu_table.txt
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

命令逻辑（USEARCH 8 以「子命令旗标」形式调用）：
  cluster_otus      usearch -cluster_otus <in> -otus <out>
  uchime_denovo     usearch -uchime_denovo <in> -uchimeout <out>
  uchime_ref        usearch -uchime_ref <in> -db <db> -uchimeout <out>
  usearch_global    usearch -usearch_global <in> -db <db> [-id X] [-otutabout f]
  derep_fulllength  usearch -derep_fulllength <in> -output <out>
  cluster_fast      usearch -cluster_fast <in> [-id X] [-centroids f]
说明书：搜索类子命令（usearch_global / uchime_ref / cluster_fast）支持 -threads；
      cluster_otus / uchime_denovo / derep_fulllength 为单线程，不注入线程参数。
"""

from __future__ import annotations

import argparse
import json
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
    "cluster_otus": "usearch -cluster_otus：UPARSE 去噪聚类，输出 OTU 代表序列",
    "uchime_denovo": "usearch -uchime_denovo：de novo 嵌合体检测（需 ;size=N 丰度标签）",
    "uchime_ref": "usearch -uchime_ref：参考数据库模式嵌合体检测",
    "usearch_global": "usearch -usearch_global：把序列比对到参考库并生成 OTU table",
    "derep_fulllength": "usearch -derep_fulllength：全长度去冗余（得到 unique 序列）",
    "cluster_fast": "usearch -cluster_fast：按相似度快速聚类",
}

# 支持 -threads 的搜索类子命令（其余为单线程）
THREADED = {"usearch_global", "uchime_ref", "cluster_fast"}

# 子命令 -> 输出旗标（CLI 统一暴露 -o/--output）
OUTPUT_FLAG = {
    "cluster_otus": "-otus",
    "uchime_denovo": "-uchimeout",
    "uchime_ref": "-uchimeout",
    "derep_fulllength": "-output",
}


class UsearchSkill(base.SkillBase):
    software = "usearch"
    binary = "usearch"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认。"""
        if override and override > 0:
            return override
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 USEARCH 命令行。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}")

        binary = self._resolve_binary()
        threads = self._effective_threads(subcommand, kw.get("threads"))

        inp = kw.get("input")
        if not inp:
            raise ValueError(f"{subcommand} 缺少必填参数 input（输入 FASTA）")
        cmd: list[str] = [binary, f"-{subcommand}", str(inp)]

        out_flag = OUTPUT_FLAG.get(subcommand)

        if subcommand == "cluster_otus":
            if kw.get("output"):
                cmd += [out_flag, str(kw["output"])]
            if kw.get("relabel"):
                cmd += ["-relabel", str(kw["relabel"])]
            if kw.get("minsize") is not None:
                cmd += ["-minsize", str(kw["minsize"])]
            if kw.get("uparseout"):
                cmd += ["-uparseout", str(kw["uparseout"])]
            if kw.get("sizein"):
                cmd.append("-sizein")

        elif subcommand == "uchime_denovo":
            if kw.get("output"):
                cmd += [out_flag, str(kw["output"])]
            if kw.get("chimeras"):
                cmd += ["-chimeras", str(kw["chimeras"])]
            if kw.get("nonchimeras"):
                cmd += ["-nonchimeras", str(kw["nonchimeras"])]
            if kw.get("uchimealns"):
                cmd += ["-uchimealns", str(kw["uchimealns"])]
            if kw.get("mindiv") is not None:
                cmd += ["-mindiv", str(kw["mindiv"])]
            if kw.get("minh") is not None:
                cmd += ["-minh", str(kw["minh"])]

        elif subcommand == "uchime_ref":
            db = kw.get("db")
            if not db:
                raise ValueError("uchime_ref 缺少必填参数 db（参考库 FASTA）")
            cmd += ["-db", str(db)]
            if kw.get("output"):
                cmd += [out_flag, str(kw["output"])]
            if kw.get("chimeras"):
                cmd += ["-chimeras", str(kw["chimeras"])]
            if kw.get("nonchimeras"):
                cmd += ["-nonchimeras", str(kw["nonchimeras"])]
            if kw.get("strand"):
                cmd += ["-strand", str(kw["strand"])]
            if kw.get("mindiv") is not None:
                cmd += ["-mindiv", str(kw["mindiv"])]
            if kw.get("minh") is not None:
                cmd += ["-minh", str(kw["minh"])]

        elif subcommand == "usearch_global":
            db = kw.get("db")
            if not db:
                raise ValueError("usearch_global 缺少必填参数 db（参考库 FASTA）")
            cmd += ["-db", str(db)]
            if kw.get("identity") is not None:
                cmd += ["-id", str(kw["identity"])]
            if kw.get("strand"):
                cmd += ["-strand", str(kw["strand"])]
            if kw.get("otutabout"):
                cmd += ["-otutabout", str(kw["otutabout"])]
            if kw.get("uc"):
                cmd += ["-uc", str(kw["uc"])]
            if kw.get("blast6out"):
                cmd += ["-blast6out", str(kw["blast6out"])]
            if kw.get("maxaccepts") is not None:
                cmd += ["-maxaccepts", str(kw["maxaccepts"])]
            if kw.get("maxhits") is not None:
                cmd += ["-maxhits", str(kw["maxhits"])]

        elif subcommand == "derep_fulllength":
            if kw.get("output"):
                cmd += [out_flag, str(kw["output"])]
            if kw.get("sizein"):
                cmd.append("-sizein")
            if kw.get("sizeout"):
                cmd.append("-sizeout")
            if kw.get("relabel"):
                cmd += ["-relabel", str(kw["relabel"])]
            if kw.get("minuniquesize") is not None:
                cmd += ["-minuniquesize", str(kw["minuniquesize"])]
            if kw.get("uc"):
                cmd += ["-uc", str(kw["uc"])]

        else:  # cluster_fast
            if kw.get("identity") is not None:
                cmd += ["-id", str(kw["identity"])]
            if kw.get("centroids"):
                cmd += ["-centroids", str(kw["centroids"])]
            if kw.get("uc"):
                cmd += ["-uc", str(kw["uc"])]
            if kw.get("sizein"):
                cmd.append("-sizein")
            if kw.get("sizeout"):
                cmd.append("-sizeout")
            if kw.get("minsize") is not None:
                cmd += ["-minsize", str(kw["minsize"])]

        # 搜索类子命令注入线程
        if subcommand in THREADED and threads:
            cmd += ["-threads", str(threads)]

        # 高级透传（慎用）
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()

        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（捕获 stdout/stderr 供 main() 重定向处理）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_common_io(p: argparse.ArgumentParser, *, output_help: str) -> None:
    p.add_argument("input", nargs="?", help="输入 FASTA（别名 --input）")
    p.add_argument("--input", help="输入 FASTA 的别名")
    p.add_argument("-o", "--output", help=output_help)
    p.add_argument("--extra-args", help="透传给 usearch 的额外参数")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="usearch-skill",
        description="usearch native 技能驱动（USEARCH 8.1.1861；⚠️ 许可受限，见 README）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # cluster_otus
    pc = sub.add_parser("cluster_otus", help=SUBCOMMANDS["cluster_otus"])
    _add_common_io(pc, output_help="OTU 代表序列输出（-otus）")
    pc.add_argument("--relabel", help="代表序列重命名前缀（-relabel）")
    pc.add_argument("--minsize", type=int, help="丢弃小于该丰度的 OTU（-minsize）")
    pc.add_argument("--uparseout", help="UPARSE 逐步输出文件（-uparseout）")
    pc.add_argument("--sizein", action="store_true", help="输入含丰度标签 ;size=N（-sizein）")
    _add_runtime_opts(pc)

    # uchime_denovo
    pd = sub.add_parser("uchime_denovo", help=SUBCOMMANDS["uchime_denovo"])
    _add_common_io(pd, output_help="UCHIME 结果表输出（-uchimeout）")
    pd.add_argument("--chimeras", help="嵌合体序列输出 FASTA（-chimeras）")
    pd.add_argument("--nonchimeras", help="非嵌合体序列输出 FASTA（-nonchimeras）")
    pd.add_argument("--uchimealns", help="嵌合体比对输出（-uchimealns）")
    pd.add_argument("--mindiv", type=float, help="最小 divergence（-mindiv）")
    pd.add_argument("--minh", type=float, help="判定嵌合体的最小 score（-minh）")
    _add_runtime_opts(pd)

    # uchime_ref
    pr = sub.add_parser("uchime_ref", help=SUBCOMMANDS["uchime_ref"])
    _add_common_io(pr, output_help="UCHIME 结果表输出（-uchimeout）")
    pr.add_argument("-d", "--db", help="参考库 FASTA（-db）")
    pr.add_argument("--chimeras", help="嵌合体序列输出 FASTA（-chimeras）")
    pr.add_argument("--nonchimeras", help="非嵌合体序列输出 FASTA（-nonchimeras）")
    pr.add_argument("--strand", help="搜索链：plus / both（-strand）")
    pr.add_argument("--mindiv", type=float, help="最小 divergence（-mindiv）")
    pr.add_argument("--minh", type=float, help="判定嵌合体的最小 score（-minh）")
    _add_runtime_opts(pr)

    # usearch_global
    pg = sub.add_parser("usearch_global", help=SUBCOMMANDS["usearch_global"])
    _add_common_io(pg, output_help="（usearch_global 用 -otutabout/-uc/-blast6out 指定输出）")
    pg.add_argument("-d", "--db", help="参考库 FASTA（-db）")
    pg.add_argument("--id", dest="identity", help="最小一致性阈值（-id，如 0.97）")
    pg.add_argument("--strand", help="搜索链：plus / both（-strand）")
    pg.add_argument("--otutabout", help="OTU table（tab 分隔）输出（-otutabout）")
    pg.add_argument("--uc", help="UC 格式输出（-uc）")
    pg.add_argument("--blast6out", help="BLAST6 格式输出（-blast6out）")
    pg.add_argument("--maxaccepts", type=int, help="每条 query 最大接受 hits 数（-maxaccepts）")
    pg.add_argument("--maxhits", type=int, help="每条 query 最大 hits 数（-maxhits）")
    _add_runtime_opts(pg)

    # derep_fulllength
    pf = sub.add_parser("derep_fulllength", help=SUBCOMMANDS["derep_fulllength"])
    _add_common_io(pf, output_help="去冗余后 unique 序列输出（-output）")
    pf.add_argument("--sizein", action="store_true", help="输入含丰度标签 ;size=N（-sizein）")
    pf.add_argument("--sizeout", action="store_true", help="输出添加 ;size=N 标签（-sizeout）")
    pf.add_argument("--relabel", help="序列重命名前缀（-relabel）")
    pf.add_argument("--minuniquesize", type=int, help="最小 unique 丰度（-minuniquesize）")
    pf.add_argument("--uc", help="UC 格式输出（-uc）")
    _add_runtime_opts(pf)

    # cluster_fast
    pk = sub.add_parser("cluster_fast", help=SUBCOMMANDS["cluster_fast"])
    _add_common_io(pk, output_help="（cluster_fast 用 -centroids/-uc 指定输出）")
    pk.add_argument("--id", dest="identity", help="最小一致性阈值（-id，如 0.97）")
    pk.add_argument("--centroids", help="聚类中心序列输出（-centroids）")
    pk.add_argument("--uc", help="UC 格式输出（-uc）")
    pk.add_argument("--sizein", action="store_true", help="输入含丰度标签 ;size=N（-sizein）")
    pk.add_argument("--sizeout", action="store_true", help="输出添加 ;size=N 标签（-sizeout）")
    pk.add_argument("--minsize", type=int, help="丢弃小于该丰度的簇（-minsize）")
    _add_runtime_opts(pk)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（仅搜索类子命令注入 -threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:18s} {v}")
        return 0
    if "--schema" in args:
        skill = UsearchSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = UsearchSkill()
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
