#!/usr/bin/env python3
"""lftp native 标准入口驱动（继承 base.SkillBase）。

lftp 主命令**无内置子命令体系**——上游调用形态是 `lftp -e "<命令串>; exit" <host>`（-e 执行
命令串后退出；典型如 NCBI SRA 下载）。本驱动把该形态收敛为三个技能层子命令：

1. CLI 直跑（人类 / Shell）：
   # get：远程路径断点续传下载（等价官方 `lftp -e "get -c <path>; exit" <host>`）
   python main.py get --host ftp-trace.ncbi.nlm.nih.gov \
       --remote-path /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra \
       --local-dir /data/sra --threads 4
   # mirror：目录镜像同步（等价官方 `lftp -e "mirror -c <dir>; exit" <host>`）
   python main.py mirror --host ftp.sra.ebi.ac.uk --remote-dir /vol1/fastq/SRR797 \
       --local-dir /data/fastq --threads 8
   # eval：自定义命令串 + host（lftp 原样执行，自动保证以 exit 结束）
   python main.py eval --host ftp.ncbi.nlm.nih.gov \
       --command "set net:timeout 30; get -c /genomes/ref.fa.gz"
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py <sub> ... --dry-run   # 只打印构建出的命令，不执行

并发与线程：
  lftp 的并发旋钮是**全局 -P N**（最大并行连接数，多文件/镜像时同时传输 N 个文件；单文件 get
  只用 1 条连接，-P 不拆片）。本驱动把 --threads 映射为 -P N：显式 --threads 优先，缺省取 meta
  optimization.per_subcommand_threads（mirror 8 / get 4 / eval 1）；有效值 <=1 时不注入 -P。
  临时目录：--tmpdir 覆盖 TMPDIR（lftp 临时文件目录；同时驱动自身的临时目录）。
白名单参数（host / remote_path / remote_dir / local_dir / command）逐项转发到 -e 命令串；
白名单外的 lftp **全局参数**经 --extra-args 透传（置于 -e 之前，如 -u user:pass）；
命令串内的额外 lftp 命令经 --extra-lftp-cmds 追加（置于 exit 之前）。
说明：lftp 命令串经 argv 传递（不经 shell），不存在 shell 注入；路径含空格/特殊字符的场景建议
用 --extra-args 走 lftp 引号语法或 eval 子命令自行构造。
"""

from __future__ import annotations

import argparse
import json
import re
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
    "get": "远程路径断点续传下载：lftp -e \"lcd <dir>; get -c <remote_path>; exit\" <host>",
    "mirror": "目录镜像同步：lftp -e \"lcd <dir>; mirror -c <remote_dir>; exit\" <host>",
    "eval": "自定义 lftp 命令串 + host：lftp -e \"<command>; exit\" <host>（原样执行）",
}


def _last_token_is_exit(cmd_s: str) -> bool:
    """判断命令串是否已以 exit 收尾（容忍尾部 ';' 与大小写）。"""
    stripped = cmd_s.rstrip().rstrip(";").strip()
    if not stripped:
        return False
    return stripped.split()[-1].lower() == "exit"


class LftpSkill(base.SkillBase):
    software = "lftp"
    binary = "lftp"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议（per_subcommand_threads）> 全局默认。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        if isinstance(per, dict):
            return int(per.get(subcommand, per.get("default", self.cpus)))
        return int(self.cpus)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 lftp 命令行。

        统一形态：[lftp] [extra_args] [-P N] -e "<命令串>" <host>
        """
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()

        host = kw.get("host")
        if not host:
            raise ValueError(f"{subcommand} 需要 --host <远端主机>（如 ftp-trace.ncbi.nlm.nih.gov）")

        # 基础 argv：binary + 白名单外 lftp 全局参数透传（置于 -e 之前）
        argv: list[str] = [binary]
        extra = kw.get("extra_args")
        if extra:
            argv += str(extra).split()

        # --threads -> 全局 -P N（最大并行连接数；仅有效值 >1 时注入）
        threads = self._effective_threads(subcommand, kw.get("threads"))
        if threads > 1:
            argv += ["-P", str(threads)]

        # -e 命令串（get/mirror 拼装；eval 原样）
        if subcommand in ("get", "mirror"):
            script = []
            local_dir = kw.get("local_dir")
            if local_dir and str(local_dir) != ".":
                script.append(f"lcd {str(local_dir)}")
            if subcommand == "get":
                remote = kw.get("remote_path")
                if not remote:
                    raise ValueError("get 需要 --remote-path <远程文件路径>")
                verb = "get -c" if kw.get("continue_", True) else "get"
                script.append(f"{verb} {str(remote)}")
            else:
                remote = kw.get("remote_dir")
                if not remote:
                    raise ValueError("mirror 需要 --remote-dir <远程目录路径>")
                verb = "mirror -c" if kw.get("continue_", True) else "mirror"
                script.append(f"{verb} {str(remote)}")
            extra_cmds = kw.get("extra_lftp_cmds")
            if extra_cmds:
                script.append(str(extra_cmds))
            script.append("exit")
            argv += ["-e", "; ".join(script), str(host)]
        else:  # eval
            command = kw.get("command")
            if not command:
                raise ValueError("eval 需要 --command <lftp 命令串>")
            cmd_s = str(command).strip()
            if not _last_token_is_exit(cmd_s):
                cmd_s += "; exit"
            argv += ["-e", cmd_s, str(host)]
        return argv


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（并发/临时目录）。"""
    p.add_argument("--threads", type=int,
                   help="并发数（映射 lftp 全局 -P N 最大并行连接数；缺省取 optimization per_subcommand_threads）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（TMPDIR，lftp 临时文件目录）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="lftp-skill",
        description="lftp native 技能驱动（get / mirror / eval；对齐官方 `lftp -e \"<命令串>; exit\" <host>` 形态）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # get：远程路径断点续传下载
    pg = sub.add_parser("get", help=SUBCOMMANDS["get"])
    pg.add_argument("--host", dest="host", default=None,
                    help="远端主机（如 ftp-trace.ncbi.nlm.nih.gov / ftp.sra.ebi.ac.uk）")
    pg.add_argument("--remote-path", dest="remote_path", default=None,
                    help="远程文件路径（如 /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra）")
    pg.add_argument("--local-dir", dest="local_dir", default=".",
                    help="本地下载目录（写入 -e 命令串的 lcd；默认当前目录）")
    pg.add_argument("--no-continue", dest="continue_", action="store_false", default=True,
                    help="关闭 -c 断点续传（默认 get -c）")
    pg.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外 lftp 全局参数原样透传（置于 -e 前，如 \"-u user:pass\"）")
    pg.add_argument("--extra-lftp-cmds", dest="extra_lftp_cmds", default=None,
                    help="追加到 -e 命令串（exit 之前）的额外 lftp 命令，多条用 ; 分隔")
    _add_runtime_opts(pg)

    # mirror：目录镜像同步
    pm = sub.add_parser("mirror", help=SUBCOMMANDS["mirror"])
    pm.add_argument("--host", dest="host", default=None,
                    help="远端主机（如 ftp.sra.ebi.ac.uk / ftp.ensembl.org）")
    pm.add_argument("--remote-dir", dest="remote_dir", default=None,
                    help="远程目录路径（如 /vol1/fastq/SRR797）")
    pm.add_argument("--local-dir", dest="local_dir", default=".",
                    help="本地镜像根目录（写入 -e 命令串的 lcd；默认当前目录）")
    pm.add_argument("--no-continue", dest="continue_", action="store_false", default=True,
                    help="关闭 -c 续传（默认 mirror -c）")
    pm.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外 lftp 全局参数原样透传（置于 -e 前）")
    pm.add_argument("--extra-lftp-cmds", dest="extra_lftp_cmds", default=None,
                    help="追加到 -e 命令串（exit 之前）的额外 lftp 命令，多条用 ; 分隔")
    _add_runtime_opts(pm)

    # eval：自定义命令串 + host
    pe = sub.add_parser("eval", help=SUBCOMMANDS["eval"])
    pe.add_argument("--host", dest="host", default=None,
                    help="远端主机（如 ftp.ncbi.nlm.nih.gov）")
    pe.add_argument("--command", dest="command", default=None,
                    help="自定义 lftp 命令串（多条用 ; 分隔；未以 exit 结尾自动补 \"; exit\"）")
    pe.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外 lftp 全局参数原样透传（置于 -e 前）")
    _add_runtime_opts(pe)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = LftpSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = LftpSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        # TMPDIR 环境变量在 __init__ 时已按默认 tmpdir 渲染 → 覆盖后重渲染
        opt = skill.meta.get("optimization", {}) or {}
        skill.env_vars = skill._render_env_vars(opt.get("env_vars", {}))

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    try:
        cmd = skill.build_command(ns.subcommand, **kw)
    except (RuntimeError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if dry_run:
        print("CMD:", " ".join(cmd))
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
