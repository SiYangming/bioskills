#!/usr/bin/env python3
"""aspera-connect native 标准入口驱动（继承 base.SkillBase）。

支持两种调用模式：
1. CLI 直跑（人类 / Shell）—— ascp 是 IBM Aspera Connect 随包的单一大命令（FASP 高速传输客户端，
   本驱动按「公共数据高速下载」场景收敛为两个技能子命令）：
   # NCBI SRA 下载（用户实装验证形态，2026-09-08 录入）：
   python main.py ascp /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./
   python main.py ascp /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 . \
       --rate 300M --key ~/.aspera/connect/etc/asperaweb_id_dsa.openssh
   # EBI ENA 下载（--host/--user/--port 覆盖；ENA 官方示例形态）：
   python main.py ascp vol1/fastq/ERR164/ERR164407/ERR164407.fastq.gz . \
       --host fasp.sra.ebi.ac.uk --user era-fasp --port 33001 --rate 300m
   python main.py version          # ascp --version（冒烟/断言）
2. Agent Function Calling / Schema 自省：
   python main.py --schema          # 打印 JSON Schema
   python main.py --list-commands   # 列出支持的子命令
   python main.py ascp <src> . --dry-run   # 只打印构建出的命令，不执行

命令逻辑（ascp 官方 CLI；--mode=recv 下载形态）：
  ascp    ascp -T -l <rate> -i <key> [-P <port>] --host=<host> --user=<user> --mode=recv <src> <dest>
          （默认参数对齐用户实装用法：-T 关加密提速度、-l 限速默认 200M、-i 默认密钥
           ~/.aspera/connect/etc/asperaweb_id_dsa.openssh、--host ftp-private.ncbi.nlm.nih.gov、
           --user anonftp、--mode=recv；NCBI 默认形态不传 -P）
  version ascp --version

说明：
- ascp 是带宽型 I/O 单进程工具，无线程参数 → 技能层 --threads 仅接受、不注入 ascp 命令；
  ascp 亦无 tmpdir 参数 → --tmpdir 仅接受、不注入（TMPDIR 由 optimization.env_vars 声明）。
- 密钥：公共数据源下载所用 asperaweb_id_dsa.openssh 位于 Connect 安装目录 etc/（用户在 3.9.6.177839
  包实装验证）；实机核查 macOS Connect 4.2.13（2024-11 安装）随包已无该 DSA 密钥（仅
  aspera_tokenauth_id_rsa 等）→ 4.2.x 基本确认不再随包提供（Linux 4.2.19.956 包未实跑核实）→ 缺失时
  经 --key 显式指定。
- ascp --version 实机输出示例（Connect 4.2.13）：'IBM Aspera Connect version 4.2.13 (820)' +
  'ascp version 4.4.3.820'（ascp 自报版本与 Connect 包版本不一致属正常）。
- Aspera 为 IBM 专有软件（非开源）：本模块只做「录入」，无真实下载/构建/安装/运行；测试为 argv
  构造断言（见 native/test/run_test.sh）。实际跑通前请以 ascp --help 核对参数形态。
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
    "ascp": "构造 ascp --mode=recv 高速下载命令（NCBI/EBI 公共数据；默认 -T -l 200M -i 默认密钥 --host ftp-private.ncbi.nlm.nih.gov --user anonftp）",
    "version": "ascp --version（冒烟/版本断言）",
}

# 默认参数（对齐用户实装验证的 NCBI SRA 下载形态，2026-09-08 录入）
DEFAULT_RATE = "200M"                                    # -l 限速（ENA 官方示例常用 300m）
DEFAULT_KEY = "~/.aspera/connect/etc/asperaweb_id_dsa.openssh"   # NCBI 公共共享密钥（随 Connect 安装）
DEFAULT_HOST = "ftp-private.ncbi.nlm.nih.gov"            # NCBI SRA FASP 主机
DEFAULT_USER = "anonftp"                                 # NCBI 免密共享用户


class AsperaConnectSkill(base.SkillBase):
    software = "aspera-connect"
    binary = "ascp"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程仅作技能层占位（ascp 无线程参数，不注入命令）。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        if isinstance(per, dict):
            return int(per.get(subcommand, per.get("default", self.cpus)))
        return int(self.cpus)

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """根据子命令与参数构建 ascp 命令行（不注入 --threads/--tmpdir：ascp 无对应参数）。"""
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}，可用: {sorted(SUBCOMMANDS)}")
        binary = self._resolve_binary()

        if subcommand == "version":
            return [binary, "--version"]

        # ---- ascp：--mode=recv 高速下载 ----
        source = kw.get("source")
        if not source:
            raise ValueError("ascp 缺少必填参数 source（远端源路径，如 "
                             "/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242）")
        dest = kw.get("dest") or "."

        cmd: list[str] = [binary, "-T"]
        # 限速 -l（默认 200M，用户实装用法；ENA 常用 300m）
        rate = kw.get("rate", DEFAULT_RATE)
        if rate:
            cmd += ["-l", str(rate)]
        # 认证密钥 -i（默认 NCBI 公共共享密钥路径；4.2+ 若随包缺失该文件则显式 --key）
        key = kw.get("key") or DEFAULT_KEY
        if key:
            cmd += ["-i", str(Path(str(key)).expanduser())]
        # 远端端口 -P（NCBI 默认形态不传；ENA 需 --port 33001）
        port = kw.get("port")
        if port:
            cmd += ["-P", str(port)]
        # 主机/用户/模式（--x= 形态与用户实装命令一致）
        host = kw.get("host", DEFAULT_HOST)
        user = kw.get("user", DEFAULT_USER)
        cmd += [f"--host={host}", f"--user={user}", "--mode=recv"]
        # 位置参数：远端源 + 本地目标（默认 .）
        cmd += [str(source), str(dest)]

        # 白名单外的上游参数（高级用法）原样透传，追加到命令末尾
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项。

    ascp 无线程/tmpdir 参数 → 两个选项仅被接受、不注入命令（记录说明），保证技能层接口统一。
    """
    p.add_argument("--threads", type=int, help="覆盖线程数（ascp 无线程参数 → 仅接受不注入）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录（ascp 无 tmpdir 参数 → 仅接受不注入）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="aspera-connect-skill",
        description="aspera-connect native 技能驱动（ascp / version；对齐 NCBI/EBI 公共数据 FASP 下载形态）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    p.add_argument("--dry-run", action="store_true", help="只打印构建出的命令，不执行")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # ascp：--mode=recv 高速下载
    pa = sub.add_parser("ascp", help=SUBCOMMANDS["ascp"])
    pa.add_argument("source", metavar="REMOTE_PATH",
                    help="远端源路径（NCBI 形态 /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242；"
                         "ENA 形态 vol1/fastq/.../<acc>.fastq.gz）")
    pa.add_argument("dest", metavar="LOCAL_PATH", nargs="?", default=".",
                    help="本地目标目录/文件（默认 .）")
    pa.add_argument("--rate", "-l", dest="rate", default=DEFAULT_RATE,
                    help=f"限速 -l（默认 {DEFAULT_RATE}；ENA 常用 300m）")
    pa.add_argument("--key", "-i", dest="key", default=DEFAULT_KEY,
                    help=f"认证密钥 -i（默认 {DEFAULT_KEY}；4.2+ 随包缺失时显式指定）")
    pa.add_argument("--host", dest="host", default=DEFAULT_HOST,
                    help=f"FASP 主机 --host（默认 {DEFAULT_HOST}；ENA 用 fasp.sra.ebi.ac.uk）")
    pa.add_argument("--user", dest="user", default=DEFAULT_USER,
                    help=f"远端用户 --user（默认 {DEFAULT_USER}；ENA 用 era-fasp）")
    pa.add_argument("--port", "-P", dest="port", type=int, default=None,
                    help="远端端口 -P（NCBI 默认形态不传；ENA 需 33001）")
    pa.add_argument("--extra-args", dest="extra_args", default=None,
                    help="白名单外的 ascp 参数原样透传（如 -k 1 断点续传；用引号包裹）")
    _add_runtime_opts(pa)

    # version：ascp --version
    pv = sub.add_parser("version", help=SUBCOMMANDS["version"])
    _add_runtime_opts(pv)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）；--dry-run 允许出现在子命令之后，预扫描剥离
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:8s} {v}")
        return 0
    if "--schema" in args:
        skill = AsperaConnectSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0
    dry_run = "--dry-run" in args
    if dry_run:
        args = [a for a in args if a != "--dry-run"]

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = AsperaConnectSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}

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
