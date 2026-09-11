#!/usr/bin/env python3
"""rnammer（RNAmmer 1.2）native 标准入口驱动。

RNAmmer 1.2（CBS DTU）是基于 HMM 的 rRNA 基因预测工具（Perl 脚本），支持 bac/arc/euk 三域，
必须搭配 HMMER 2.x 与 Perl 模块 XML::Simple 运行。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py scan genome.fasta --kingdom bac --multi \\
       -f rRNA.fasta -h rRNA.hmmreport -xml rRNA.xml -gff rRNA.gff2
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

说明：rnammer 无线程参数（-multi 自带双链并行），--threads 仅作协议位不注入命令行；
--tmpdir 注入 TMPDIR 环境变量。rnammer 二进制需宿主机安装（RNAmmer 源码为 CBS DTU 官网
注册制下载，见 README「环境安装（官方渠道无镜像：宿主机安装）」）。
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
    "scan": "rnammer：HMM 法 rRNA 基因预测（-S bac|arc|euk，默认 -multi 双链全部类型；-f/-h/-xml/-gff 输出）",
}


class RnammerSkill(base.SkillBase):
    software = "rnammer"
    binary = "rnammer"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/rnammer/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_rnammer(self) -> str:
        """解析 rnammer 可执行文件，找不到时给出注册下载 + 路径配置指引。"""
        path = shutil.which(self.binary or self.software)
        if not path:
            raise RuntimeError(
                "未找到可执行文件 'rnammer'：RNAmmer 1.2 源码为 CBS DTU 官网注册制下载"
                "（https://services.healthtech.dtu.dk/services/RNAmmer-1.2/ ，需 edu 邮箱申请下载链接；"
                "替代来源：自建归档镜像 https://github.com/SiYangming/rnammer-1.2 ，已归档/只读、私有需授权），"
                "请先注册下载 rnammer-1.2 源码并完成安装（见 README「环境安装（官方渠道无镜像：宿主机安装）」，"
                "或 bash native/install.sh --method manual --rnammer-tarball <rnammer-1.2.tar.gz>）；"
                "安装后须就地配置脚本内 INSTALL_PATH（rnammer-1.2 安装目录）与 HMMSEARCH_BINARY"
                "（HMMER2 的 hmmsearch），并把 rnammer 加入 PATH。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 rnammer 命令行（rnammer 无线程参数，不注入 --threads）。"""
        if subcommand != "scan":
            raise RuntimeError(f"未知子命令: {subcommand}")

        kingdom = kw.get("kingdom")
        if not kingdom:
            raise RuntimeError("scan 需要 --kingdom/-S（arc|bac|euk）")
        kingdom = str(kingdom).lower()
        if kingdom not in ("arc", "bac", "euk"):
            raise RuntimeError(f"--kingdom/-S 仅支持 arc|bac|euk（收到: {kingdom}）")

        genome = kw.get("genome_fasta")
        if not genome:
            raise RuntimeError("scan 需要 genome_fasta（基因组 FASTA，位置参数）")

        binary = self._resolve_rnammer()
        cmd: list[str] = [binary, "-S", kingdom]

        # -multi：双链并行预测全部类型（默认开启；--multi 自带并行，无需线程参数）
        if kw.get("multi", True):
            cmd.append("-multi")
        if kw.get("molecules"):
            cmd += ["-m", str(kw["molecules"])]
        if kw.get("out_fasta"):
            cmd += ["-f", str(kw["out_fasta"])]
        if kw.get("hmmreport"):
            cmd += ["-h", str(kw["hmmreport"])]
        if kw.get("xml"):
            cmd += ["-xml", str(kw["xml"])]
        if kw.get("gff"):
            cmd += ["-gff", str(kw["gff"])]

        # 输入基因组 FASTA 为位置参数（放在所有选项之后）
        cmd.append(str(genome))

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
        prog="rnammer-skill",
        description="rnammer（RNAmmer 1.2）native 技能驱动（HMM 法 rRNA 基因预测；-multi 双链并行）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # add_help=False：rnammer 原生 -h 为 hmmreport，需用 -h 短选项，故手动提供 --help
    ps = sub.add_parser("scan", help=SUBCOMMANDS["scan"], add_help=False)
    ps.add_argument("-S", "--kingdom", required=True, help="域模型：arc|bac|euk（rnammer 必填）")
    ps.add_argument("--multi", dest="multi", action="store_true",
                    help="双链并行预测全部类型（默认开启，注入 -multi）")
    ps.add_argument("--no-multi", dest="multi", action="store_false",
                    help="关闭 -multi（仅按 -m 指定类型预测）")
    ps.set_defaults(multi=True)
    ps.add_argument("-m", "--molecules",
                    help="分子类型（逗号分隔）：tsu|ssu|lsu|tsu,ssu,lsu")
    ps.add_argument("-f", "--out-fasta", dest="out_fasta", help="预测 rRNA 序列输出 FASTA")
    ps.add_argument("-h", "--hmmreport", help="HMMER 搜索报告输出文件（rnammer 原生 -h）")
    ps.add_argument("-xml", "--xml", dest="xml", help="预测结果 XML 输出文件")
    ps.add_argument("-gff", "--gff", dest="gff", help="预测结果 GFF2 输出文件")
    ps.add_argument("--extra-args", dest="extra_args",
                    help="透传给 rnammer 的额外参数（高级用法，慎用）")
    ps.add_argument("genome_fasta", help="输入基因组 FASTA（位置参数）")
    ps.add_argument("--help", action="help", help="显示本子命令帮助并退出")
    _add_runtime_opts(ps)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录，协议位）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（协议位；rnammer 无线程参数，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = RnammerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = RnammerSkill()
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

    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
