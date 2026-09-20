#!/usr/bin/env python3
"""system_setup: 宿主机环境引导编排（来源 01.CentOS_System_Configuration）

将教学章两份脚本切成可复用 stages：
  configure_repos → install_base_packages → harden_ssh → configure_firewall
  → configure_selinux_limits → configure_user_env → setup_httpd → setup_mariadb
  → prepare_soft_dirs → [可选] install_sysoft_runtimes

模式（与其它 subworkflow 一致）：
  --list-stages / --dry-run（默认）/ --real（需 --confirm-root；多数步骤要 root）

路径与用户名全部参数化，禁止写死 /home/train、/opt/biosoft（可用默认值显式传入）。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_HELPER = _HERE / "system_setup_stages.sh"

_STAGES = [
    "configure_repos",
    "install_base_packages",
    "harden_ssh",
    "configure_firewall",
    "configure_selinux_limits",
    "configure_user_env",
    "setup_httpd",
    "setup_mariadb",
    "prepare_soft_dirs",
    "install_sysoft_runtimes",
]


def _defaults(ns: argparse.Namespace) -> argparse.Namespace:
    user = ns.train_user
    home = ns.train_home or f"/home/{user}"
    ns.train_home = home
    if not ns.software_cache:
        ns.software_cache = str(Path(home) / "software")
    if not ns.mysql_datadir:
        # 原脚本 /home/.mysql → 参数化为 <home 的父目录>/.mysql
        ns.mysql_datadir = str(Path(home).parent / ".mysql")
    return ns


def _stage_cmd(stage: str, a: argparse.Namespace, dry_run: bool) -> list[str]:
    if not _HELPER.exists():
        return ["<MISSING>", str(_HELPER), stage]
    cmd = [
        "bash",
        str(_HELPER),
        stage,
        "--train-user", a.train_user,
        "--train-home", a.train_home,
        "--bio-soft-root", a.bio_soft_root,
        "--sys-soft-root", a.sys_soft_root,
        "--mysql-datadir", a.mysql_datadir,
        "--software-cache", a.software_cache,
        "--http-ports", a.http_ports,
        "--base-packages", a.base_packages,
    ]
    if dry_run:
        cmd.append("--dry-run")
    if a.enable_sysoft_runtimes:
        cmd.append("--enable-sysoft-runtimes")
    return cmd


def _selected_stages(spec: str) -> list[str]:
    if not spec or spec.strip().lower() == "all":
        return list(_STAGES)
    wanted = [s.strip() for s in spec.split(",") if s.strip()]
    unknown = [s for s in wanted if s not in _STAGES]
    if unknown:
        raise SystemExit(f"[ERROR] 未知 stage: {unknown}；合法: {_STAGES}")
    return wanted


def run_stages(a: argparse.Namespace, real: bool) -> int:
    a = _defaults(a)
    stages = _selected_stages(a.stages)
    if real and not a.confirm_root:
        print(
            "[ERROR] --real 必须同时传 --confirm-root（将改写系统配置；先 --dry-run 审阅）",
            file=sys.stderr,
        )
        return 2
    if real and os.geteuid() != 0:
        print("[WARN] 当前非 root；部分 stage 可能失败（仍继续尝试）", file=sys.stderr)

    dry_run = not real
    for name in stages:
        if name == "install_sysoft_runtimes" and not a.enable_sysoft_runtimes:
            print(f"[{name}]: SKIP（未开 --enable-sysoft-runtimes；现代路线请用 conda）")
            continue
        cmd = _stage_cmd(name, a, dry_run=dry_run)
        print(f"[{name}]: " + " ".join(map(str, cmd)))
        if real:
            if cmd and cmd[0] == "<MISSING>":
                print(f"  <MISSING> {cmd[1]}", file=sys.stderr)
                continue
            subprocess.run(cmd, check=True)
    return 0


def main(argv=None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]

    if "--list-stages" in argv:
        print(
            json.dumps(
                {
                    "id": "custom_system_setup",
                    "canonical": "system_setup",
                    "source": "01.CentOS_System_Configuration",
                    "stages": _STAGES,
                    "helper": str(_HELPER),
                    "helper_exists": _HELPER.exists(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    p = argparse.ArgumentParser(
        description="subworkflow/system_setup — 宿主机环境引导（01 章）"
    )
    p.add_argument("--train-user", default="train")
    p.add_argument("--train-home", default="", help="空 = /home/<train-user>")
    p.add_argument("--bio-soft-root", default="/opt/biosoft")
    p.add_argument("--sys-soft-root", default="/opt/sysoft")
    p.add_argument("--mysql-datadir", default="")
    p.add_argument("--software-cache", default="")
    p.add_argument("--http-ports", default="80,8080,3306")
    p.add_argument(
        "--base-packages",
        default=(
            "httpd mariadb mariadb-server mariadb-devel lftp ftp "
            "gd gd-devel cmake gsl gsl-devel gnuplot gmp-devel libffi-devel"
        ),
    )
    p.add_argument(
        "--stages",
        default="all",
        help="逗号分隔 stage id，或 all",
    )
    p.add_argument(
        "--enable-sysoft-runtimes",
        action="store_true",
        help="执行教学预编译 GCC/Python/R 等解压（默认跳过）",
    )
    p.add_argument(
        "--confirm-root",
        action="store_true",
        help="确认允许 --real 改写系统配置",
    )
    p.add_argument(
        "--real",
        action="store_true",
        help="真实执行（默认 dry-run）",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="仅打印（默认；可显式写出）",
    )
    args = p.parse_args(argv)
    if args.real and args.dry_run:
        print("[ERROR] --real 与 --dry-run 互斥", file=sys.stderr)
        return 2
    return run_stages(args, real=args.real)


if __name__ == "__main__":
    raise SystemExit(main())
