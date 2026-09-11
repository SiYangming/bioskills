#!/usr/bin/env python3
"""recon（RECON：REpeat CONstructor）native 标准入口驱动。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）：
   python main.py pipeline seqnames.msps..  # 见下完整示例
   python main.py pipeline seqnames msps.msp -o recon_work --sections 1
   python main.py eledef  seqnames msps.msp --method single -o recon_work
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令

所有子命令接受 --threads / --tmpdir（RECON 四阶段为串行 C 程序，--threads 仅作接口一致保留、不注入）。

CLI 事实（以 bioconda recon=1.10 包内 bin/ 与实际 usage 为准）：
- 主驱动：run_recon.sh <bin_dir> <seq_list> <msp_file> [num_sections] [work_dir]
  （四阶段流水线，输出 summary/eles + summary/families；work_dir 须已存在）
- 阶段 1：eledef <seq_list> <msp_file> single|double [cutoff] [-l level]
- 其余阶段：eleredef / edgeredef / famdef（本驱动不单独暴露：需 run_recon.sh 的
  tmp/tmp2 软链接与共享目录编排，单独调用易误用）
- 包内另有 imagespread（RECON 1.08 兼容 shim，由 run_recon.sh 自动调用）
"""
from __future__ import annotations

import argparse
import json
import os
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
    "pipeline": "run_recon.sh：跑完整四阶段流水线（eledef→eleredef→edgeredef→famdef），输出 summary/eles + summary/families",
    "eledef": "eledef：仅阶段 1（MSP → 初始元素库 ele_store/ 与 summary/naive_eles）",
}


class ReconSkill(base.SkillBase):
    software = "recon"
    binary = "eledef"

    def __init__(self, meta_path: str | Path | None = None):
        # 单 meta 模式下 meta.yaml 位于软件级 modules/recon/meta.yaml（不在 native/ 下），
        # 显式指向它，使 --schema / optimization 等真正读到配置。
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
        """解析配套可执行文件（run_recon.sh / eledef），带清晰报错。"""
        path = shutil.which(tool)
        if not path:
            raise RuntimeError(
                f"未找到可执行文件 '{tool}'，请先通过 Conda/Docker/Apptainer 安装 "
                "（bioconda recon=1.10 会同时提供 run_recon.sh 与 eledef/eleredef/edgeredef/famdef）。"
            )
        return path

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 RECON 命令行。"""
        _ = self._effective_threads(subcommand, kw.get("threads"))  # 串行工具，仅统一接口

        if subcommand == "pipeline":
            run_recon = self._resolve_tool("run_recon.sh")
            seq_list = kw.get("seq_list")
            msp = kw.get("msp")
            if not seq_list:
                raise RuntimeError("pipeline 需要 seq_list（序列名清单文件）")
            if not msp:
                raise RuntimeError("pipeline 需要 msp（MSP 比对文件）")
            # run_recon.sh 以 run_recon.sh 自身所在目录作为默认 bin_dir（含四阶段二进制）
            bin_dir = kw.get("bin_dir") or str(Path(run_recon).parent)
            sections = kw.get("sections")
            sections = 1 if sections is None else int(sections)
            # 官方 usage：run_recon.sh bin_dir seq_list msp_file [num_sections] [work_dir]
            cmd: list[str] = [run_recon, str(bin_dir), str(seq_list), str(msp), str(sections)]
            workdir = kw.get("workdir")
            if workdir:
                # run_recon.sh 用 realpath 解析 work_dir，路径必须已存在（main() 已 mkdir）
                cmd.append(str(workdir))
            return cmd

        if subcommand == "eledef":
            eledef = self._resolve_tool("eledef")
            seq_list = kw.get("seq_list")
            msp = kw.get("msp")
            if not seq_list:
                raise RuntimeError("eledef 需要 seq_list（序列名清单文件）")
            if not msp:
                raise RuntimeError("eledef 需要 msp（MSP 比对文件）")
            method = kw.get("method") or "single"
            if method not in ("single", "double"):
                raise RuntimeError("--method 仅支持 single|double")
            # 官方 usage：eledef seq_list msp_file single|double [cutoff] [-l level]
            cmd = [eledef, str(seq_list), str(msp), str(method)]
            cutoff = kw.get("cutoff")
            if cutoff is not None:
                cmd.append(str(cutoff))
            level = kw.get("level")
            if level is not None:
                cmd += ["-l", str(level)]
            return cmd

        raise RuntimeError(f"未知子命令: {subcommand}")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="recon-skill",
        description="recon（RECON：REpeat CONstructor）native 技能驱动（重复家族识别/分类；串行四阶段流水线）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # pipeline: run_recon.sh <bin_dir> <seq_list> <msp_file> [num_sections] [work_dir]
    pp = sub.add_parser("pipeline", help=SUBCOMMANDS["pipeline"])
    pp.add_argument("seq_list", help="序列名清单文件（首行计数，其后每行一个序列名，须字典序排序）")
    pp.add_argument("msp", help="MSP 比对文件（score %iden q_start q_end q_name s_start s_end s_name）")
    pp.add_argument("-o", "--workdir", help="工作目录（产物写入此处；缺省在临时目录下新建并回显）")
    pp.add_argument("--sections", type=int, default=1, help="num_sections（仅旧 1.08 imagespread 使用；新版忽略）")
    pp.add_argument("--bin-dir", dest="bin_dir", help="可执行文件目录（默认取 run_recon.sh 所在目录）")
    _add_runtime_opts(pp)

    # eledef: eledef <seq_list> <msp_file> single|double [cutoff] [-l level]
    pe = sub.add_parser("eledef", help=SUBCOMMANDS["eledef"])
    pe.add_argument("seq_list", help="序列名清单文件（首行计数，其后每行一个序列名，须字典序排序）")
    pe.add_argument("msp", help="MSP 比对文件")
    pe.add_argument("--method", choices=("single", "double"), default="single", help="聚类方法（默认 single）")
    pe.add_argument("--cutoff", type=float, help="可选聚类 cutoff（缺省用内建默认）")
    pe.add_argument("-l", "--level", type=int, help="日志级别（0=silent 1=error 2=warn 3=info 4=debug）")
    pe.add_argument("-o", "--workdir", help="工作目录（eledef 在 CWD 写 ele_store/；指定则先 cd 到此目录）")
    _add_runtime_opts(pe)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（RECON 串行，不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（同时注入 TMPDIR）")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = ReconSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = ReconSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    # 工作目录：建目录并 cd（RECON 各阶段写 CWD；run_recon.sh 的 work_dir 须已存在）。
    # 输入路径在 chdir 前解析为绝对路径，避免相对路径失效。
    workdir = kw.get("workdir")
    if workdir:
        try:
            wd = Path(workdir).resolve()
            wd.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            print(f"[ERROR] 无法创建工作目录 {workdir}: {exc}", file=sys.stderr)
            return 1
        for key in ("seq_list", "msp"):
            if kw.get(key):
                kw[key] = str(Path(kw[key]).resolve())
        os.chdir(wd)
        kw["workdir"] = str(wd)

    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    # run_recon.sh 把工作目录路径 echo 到 stdout；非捕获类子命令直接继承退出码
    if not result.stdout and not result.stderr:
        return result.returncode
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
