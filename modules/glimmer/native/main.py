#!/usr/bin/env python3
"""Glimmer3（glimmer）native 标准入口驱动。

Glimmer3 是原核生物基因预测系统，上游以「一组命令行程序」发布，典型教学四步链为：
  long-orfs → extract → build-icm → glimmer3
本驱动包装其中三步（extract 为同包原生程序，见 README「实战示例」）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py long_orfs genome.fna -o tag.longorfs -n -t 1.15
   python main.py build_icm tag.train -o tag.icm -r
   python main.py glimmer3 genome.fna tag.icm -o tag -g 110 -t 30
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

每个子命令支持 --threads / --tmpdir 运行期覆盖；但 Glimmer3 各程序为单线程实现，
--threads 仅作协议位（记录用，不注入命令行），--tmpdir 注入 TMPDIR 环境变量。

CLI 事实（按 glimmer302b 源码 usage 核实，bioconda glimmer=3.02）：
- long-orfs [options] <sequence-file> <output-file>
- build-icm [options] output_file < input-file（输入从 stdin 读，驱动代为重定向）
- glimmer3  [options] <sequence-file> <icm-file> <tag>（输出 <tag>.predict / <tag>.detail）
驱动层 -o/--output 表示主产物（坐标文件 / ICM / 输出前缀）；各程序原生的 -o（--max_olap）
改由 --max-olap 暴露。
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
    "long_orfs": "long-orfs：在基因组 FASTA 中寻找长且不重叠的 ORF，作为训练集坐标（教学第 1 步）",
    "build_icm": "build-icm：从训练序列（stdin）构建插值上下文模型 ICM（教学第 3 步）",
    "glimmer3": "glimmer3：用 ICM 在基因组中预测基因，输出 <tag>.predict / <tag>.detail（教学第 4 步）",
}

# 子命令 → 实际底层程序名
PROGRAM = {
    "long_orfs": "long-orfs",
    "build_icm": "build-icm",
    "glimmer3": "glimmer3",
}


class GlimmerSkill(base.SkillBase):
    software = "glimmer"
    binary = "glimmer3"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/glimmer/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / per_subcommand_threads 等真正读到优化配置。
        if meta_path is None:
            meta_path = _HERE.parent / "meta.yaml"
        super().__init__(meta_path)

    def _resolve_tool(self, tool: str) -> str:
        """返回可执行文件路径；未安装时退回命令名。

        --dry-run / --help 契约（test/run_test.sh）在无二进制机器上也应可跑，
        因此这里不抛错；真跑时由 base.run_command 在 FileNotFoundError 上给出清晰报错。
        """
        return shutil.which(tool) or tool

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建底层程序命令行（不执行）。"""
        if subcommand == "long_orfs":
            return self._build_long_orfs(kw)
        if subcommand == "build_icm":
            return self._build_build_icm(kw)
        if subcommand == "glimmer3":
            return self._build_glimmer3(kw)
        raise RuntimeError(f"未知子命令: {subcommand}")

    # -- long-orfs [options] <sequence-file> <output-file> ----------------- #
    def _build_long_orfs(self, kw: dict) -> list[str]:
        sequence = kw.get("sequence")
        output = kw.get("output")
        if not sequence:
            raise RuntimeError("long_orfs 需要 --sequence（输入基因组 FASTA）")
        if not output:
            raise RuntimeError("long_orfs 需要 -o/--output（输出 ORF 坐标文件）")

        cmd: list[str] = [self._resolve_tool(PROGRAM["long_orfs"])]
        if kw.get("no_header"):
            cmd.append("-n")
        if kw.get("cutoff") is not None:
            cmd += ["-t", str(kw["cutoff"])]
        if kw.get("max_olap") is not None:
            cmd += ["-o", str(kw["max_olap"])]
        if kw.get("min_len") is not None:
            cmd += ["-g", str(kw["min_len"])]
        if kw.get("linear"):
            cmd.append("-l")
        if kw.get("length_opt"):
            cmd.append("-L")
        if kw.get("without_stops"):
            cmd.append("-w")
        if kw.get("fixed"):
            cmd.append("-f")
        if kw.get("trans_table") is not None:
            cmd += ["-z", str(kw["trans_table"])]
        if kw.get("start_codons"):
            cmd += ["-A", str(kw["start_codons"])]
        if kw.get("stop_codons"):
            cmd += ["-Z", str(kw["stop_codons"])]
        cmd += [str(sequence), str(output)]
        return self._append_extra(cmd, kw)

    # -- build-icm [options] output_file < input-file --------------------- #
    def _build_build_icm(self, kw: dict) -> list[str]:
        output = kw.get("output")
        if not output:
            raise RuntimeError("build_icm 需要 -o/--output（输出 ICM 模型文件）")
        if not kw.get("train"):
            raise RuntimeError("build_icm 需要位置参数 train（训练序列 FASTA，经 stdin 传入 build-icm）")

        cmd: list[str] = [self._resolve_tool(PROGRAM["build_icm"])]
        if kw.get("reverse"):
            cmd.append("-r")
        if kw.get("depth") is not None:
            cmd += ["-d", str(kw["depth"])]
        if kw.get("period") is not None:
            cmd += ["-p", str(kw["period"])]
        if kw.get("window") is not None:
            cmd += ["-w", str(kw["window"])]
        if kw.get("ignore_stops"):
            cmd.append("-F")
        if kw.get("text"):
            cmd.append("-t")
        cmd.append(str(output))
        return self._append_extra(cmd, kw)

    # -- glimmer3 [options] <sequence-file> <icm-file> <tag> --------------- #
    def _build_glimmer3(self, kw: dict) -> list[str]:
        genome = kw.get("genome")
        icm = kw.get("icm")
        output = kw.get("output")
        if not genome:
            raise RuntimeError("glimmer3 需要位置参数 genome（输入基因组 FASTA）")
        if not icm:
            raise RuntimeError("glimmer3 需要位置参数 icm（ICM 模型文件）")
        if not output:
            raise RuntimeError("glimmer3 需要 -o/--output（输出前缀 <tag>，产出 <tag>.predict/.detail）")

        cmd: list[str] = [self._resolve_tool(PROGRAM["glimmer3"])]
        if kw.get("max_olap") is not None:
            cmd += ["-o", str(kw["max_olap"])]
        if kw.get("gene_len") is not None:
            cmd += ["-g", str(kw["gene_len"])]
        if kw.get("threshold") is not None:
            cmd += ["-t", str(kw["threshold"])]
        if kw.get("linear"):
            cmd.append("-l")
        if kw.get("trans_table") is not None:
            cmd += ["-z", str(kw["trans_table"])]
        if kw.get("rbs_pwm"):
            cmd += ["-b", str(kw["rbs_pwm"])]
        if kw.get("gc_percent") is not None:
            cmd += ["-C", str(kw["gc_percent"])]
        if kw.get("start_codons"):
            cmd += ["-A", str(kw["start_codons"])]
        if kw.get("stop_codons"):
            cmd += ["-Z", str(kw["stop_codons"])]
        if kw.get("start_probs"):
            cmd += ["-P", str(kw["start_probs"])]
        if kw.get("separate_genes"):
            cmd.append("-M")
        if kw.get("extend"):
            cmd.append("-X")
        if kw.get("no_indep"):
            cmd.append("-r")
        if kw.get("ignore_score_len") is not None:
            cmd += ["-q", str(kw["ignore_score_len"])]
        if kw.get("first_codon"):
            cmd.append("-f")
        cmd += [str(genome), str(icm), str(output)]
        return self._append_extra(cmd, kw)

    @staticmethod
    def _append_extra(cmd: list[str], kw: dict) -> list[str]:
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    # -- 执行（build_icm 需把 train 重定向到 stdin） ------------------------ #
    def run(self, subcommand: str, **kw) -> base.RunResult:
        args = self.build_command(subcommand, **kw)
        if subcommand == "build_icm":
            train = kw.get("train")
            run_env = os.environ.copy()
            run_env.update(self.env_vars)
            try:
                with open(str(train), "rb") as fh:
                    proc = subprocess.run(
                        args, stdin=fh, env=run_env,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, check=False,
                    )
            except FileNotFoundError as exc:
                raise RuntimeError(f"可执行文件未找到: {args[0]}") from exc
            return base.RunResult(command=args, returncode=proc.returncode,
                                  stdout=proc.stdout or "", stderr=proc.stderr or "")
        return super().run(subcommand, **kw)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="glimmer-skill",
        description="Glimmer3（glimmer）native 技能驱动（原核基因预测；单线程，--threads 作协议位）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # long_orfs: long-orfs [options] <sequence-file> <output-file>
    pl = sub.add_parser("long_orfs", help=SUBCOMMANDS["long_orfs"])
    pl.add_argument("-sequence", "--sequence", dest="sequence", required=True,
                    help="输入基因组 FASTA（long-orfs 的 <sequence-file>，位置参数）")
    pl.add_argument("-o", "-output", "--output", dest="output", required=True,
                    help="输出 ORF 坐标文件（long-orfs 的 <output-file>，位置参数）")
    pl.add_argument("-n", "--no-header", dest="no_header", action="store_true",
                    help="不在输出中包含表头等说明信息（long-orfs -n/--no_header）")
    pl.add_argument("-t", "--cutoff", type=float,
                    help="熵距离截断：只保留熵距离分数低于该值的基因（long-orfs -t，教学常用 1.15）")
    pl.add_argument("--max-olap", dest="max_olap", type=int,
                    help="最大允许重叠长度（long-orfs 原生 -o/--max_olap；驱动 -o 保留给 --output）")
    pl.add_argument("-g", "--min-len", dest="min_len", type=int,
                    help="只考虑长度 >= n 的基因（long-orfs -g/--min_len）")
    pl.add_argument("-l", "--linear", action="store_true", help="假定线性基因组（不做环形 wraparound）")
    pl.add_argument("-L", "--length-opt", dest="length_opt", action="store_true",
                    help="以最大化基因总长度（而非数量）选择最小基因长度（long-orfs -L）")
    pl.add_argument("-w", "--without-stops", dest="without_stops", action="store_true",
                    help="输出坐标不包含终止密码子（long-orfs -w）")
    pl.add_argument("-f", "--fixed", action="store_true",
                    help="不自动确定最小基因长度（long-orfs -f/--fixed）")
    pl.add_argument("-z", "--trans-table", dest="trans_table", type=int,
                    help="终止密码子所用的 Genbank 翻译表编号（long-orfs -z）")
    pl.add_argument("-A", "--start-codons", dest="start_codons",
                    help="逗号分隔的起始密码子列表（如 atg,gtg；long-orfs -A）")
    pl.add_argument("-Z", "--stop-codons", dest="stop_codons",
                    help="逗号分隔的终止密码子列表（如 tag,tga,taa；long-orfs -Z）")
    pl.add_argument("--extra-args", dest="extra_args",
                    help="透传给 long-orfs 的额外参数（如 -E/-i，高级用法，慎用）")
    pl.add_argument("--dry-run", action="store_true", help="仅打印将执行的命令行，不真正运行")
    _add_runtime_opts(pl)

    # build_icm: build-icm [options] output_file < input-file
    pb = sub.add_parser("build_icm", help=SUBCOMMANDS["build_icm"])
    pb.add_argument("train", help="训练序列 FASTA（extract 产出；驱动重定向到 build-icm stdin）")
    pb.add_argument("-o", "-output", "--output", dest="output", required=True,
                    help="输出 ICM 模型文件（build-icm 的 output_file，位置参数）")
    pb.add_argument("-r", "--reverse", action="store_true",
                    help="用输入序列的反向（reverse）构建模型（build-icm -r）")
    pb.add_argument("-d", "--depth", type=int, help="模型深度（build-icm -d）")
    pb.add_argument("-p", "--period", type=int, help="模型周期（build-icm -p）")
    pb.add_argument("-w", "--window", type=int, help="模型窗口长度（build-icm -w）")
    pb.add_argument("-F", "--ignore-stops", dest="ignore_stops", action="store_true",
                    help="忽略含框内终止密码子的输入串（build-icm -F）")
    pb.add_argument("-t", "--text", action="store_true",
                    help="以文本形式输出模型（仅调试；build-icm -t）")
    pb.add_argument("--extra-args", dest="extra_args",
                    help="透传给 build-icm 的额外参数（高级用法，慎用）")
    pb.add_argument("--dry-run", action="store_true", help="仅打印将执行的命令行，不真正运行")
    _add_runtime_opts(pb)

    # glimmer3: glimmer3 [options] <sequence-file> <icm-file> <tag>
    pg = sub.add_parser("glimmer3", help=SUBCOMMANDS["glimmer3"])
    pg.add_argument("genome", help="输入基因组 FASTA（glimmer3 的 <sequence-file>，位置参数）")
    pg.add_argument("icm", help="ICM 模型文件（glimmer3 的 <icm-file>，build_icm 产出）")
    pg.add_argument("-o", "-output", "--output", dest="output", required=True,
                    help="输出前缀 <tag>（产出 <tag>.predict / <tag>.detail）")
    pg.add_argument("--max-olap", dest="max_olap", type=int,
                    help="最大允许重叠长度（glimmer3 原生 -o/--max_olap；驱动 -o 保留给 --output）")
    pg.add_argument("-g", "--gene-len", dest="gene_len", type=int,
                    help="最小基因长度（glimmer3 -g/--gene_len，教学常用 110）")
    pg.add_argument("-t", "--threshold", type=float,
                    help="判定为基因的分数阈值（glimmer3 -t/--threshold，教学常用 30）")
    pg.add_argument("-l", "--linear", action="store_true", help="假定线性基因组（不做环形 wraparound）")
    pg.add_argument("-z", "--trans-table", dest="trans_table", type=int,
                    help="终止密码子所用的 Genbank 翻译表编号（glimmer3 -z）")
    pg.add_argument("-b", "--rbs-pwm", dest="rbs_pwm",
                    help="核糖体结合位点 PWM 文件（glimmer3 -b/--rbs_pwm）")
    pg.add_argument("-C", "--gc-percent", dest="gc_percent", type=float,
                    help="独立模型的 GC 百分比（glimmer3 -C，如 45.2）")
    pg.add_argument("-A", "--start-codons", dest="start_codons",
                    help="逗号分隔的起始密码子列表（glimmer3 -A）")
    pg.add_argument("-Z", "--stop-codons", dest="stop_codons",
                    help="逗号分隔的终止密码子列表（glimmer3 -Z）")
    pg.add_argument("-P", "--start-probs", dest="start_probs",
                    help="各起始密码子使用概率（glimmer3 -P，如 0.6,0.35,0.05）")
    pg.add_argument("-M", "--separate-genes", dest="separate_genes", action="store_true",
                    help="输入为独立基因的多序列 FASTA，各自打分、不做重叠规则（glimmer3 -M）")
    pg.add_argument("-X", "--extend", action="store_true",
                    help="允许评分延伸到序列两端的 ORF（glimmer3 -X）")
    pg.add_argument("-r", "--no-indep", dest="no_indep", action="store_true",
                    help="不使用独立概率打分列（glimmer3 -r）")
    pg.add_argument("-q", "--ignore-score-len", dest="ignore_score_len", type=int,
                    help="对长度 >= n 的基因不做初始打分过滤（glimmer3 -q）")
    pg.add_argument("-f", "--first-codon", dest="first_codon", action="store_true",
                    help="以 ORF 的第一个密码子作为起始密码子（glimmer3 -f）")
    pg.add_argument("--extra-args", dest="extra_args",
                    help="透传给 glimmer3 的额外参数（高级用法，慎用）")
    pg.add_argument("--dry-run", action="store_true", help="仅打印将执行的命令行，不真正运行")
    _add_runtime_opts(pg)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。

    Glimmer3 各程序为单线程实现：--threads 仅作协议位记录（不注入命令行）。
    """
    p.add_argument("--threads", type=int, help="线程数（Glimmer3 单线程，仅作协议位，不注入命令行）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = GlimmerSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = GlimmerSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir", "dry_run") and v is not None}
    # --threads 仅作协议位：记录但不注入（Glimmer3 单线程）
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

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
