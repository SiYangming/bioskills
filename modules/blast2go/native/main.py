#!/usr/bin/env python3
"""blast2go native 标准入口驱动（Blast2GO 3.3 客户端 + b2g4pipe v2.5 命令行，Java）。

Blast2GO 许可受限（需注册/订阅获取发行包），官方调用形如：
    # 命令行 GO 注释（b2g4pipe）
    java -cp "*:ext/*:" es.blast2go.prog.B2GAnnotPipe -in nr.xml -out go -annot -dat -annex
    # 本地注释库（local_b2g_db + install_blast2goDB.sh，依赖 MySQL/Perl）
    perl install_blast2goDB.sh
    # 图形客户端（Blast2GO 3.3）
    <Blast2GO>/Blast2GO

本驱动两种模式：
1. CLI 直跑（人类 / Shell）：
   python main.py annot -in nr.xml -out go --b2g-dir ~/software/b2g4pipe
   python main.py install_db --db-home ~/software/blast2go-db
   python main.py client --blast2go-home ~/software/Blast2GO
   python main.py --schema | --list-commands
2. Agent Function Calling / Schema 自省。

自动优化：
- Java 工具：JVM 参数经 JAVA_OPTS 环境变量透传（见 meta optimization.env_vars；--java-opts 覆盖）。
- 入口定位：b2g4pipe 目录优先 --b2g-dir / B2G4PIPE_HOME；客户端优先 --blast2go-home / BLAST2GO_HOME。
- JVM 临时目录经 -Djava.io.tmpdir 指向 self.tmpdir。
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
    "annot": "b2g4pipe B2GAnnotPipe 命令行 GO 注释（java -cp <b2g-dir>/*:<b2g-dir>/ext/*）",
    "install_db": "安装 Blast2GO 本地注释库（local_b2g_db 的 install_blast2goDB.sh，依赖 MySQL/Perl）",
    "client": "启动 Blast2GO 3.3 图形客户端（<blast2go-home>/Blast2GO）",
}

_ANNOT_MAIN = "es.blast2go.prog.B2GAnnotPipe"


class Blast2GOSkill(base.SkillBase):
    software = "blast2go"
    binary = "java"

    # -- 入口定位（惰性解析，测试可 monkeypatch） ------------------------- #
    def _resolve_java(self) -> str:
        path = base.which("java")
        if not path:
            raise RuntimeError(
                "未找到 java：Blast2GO / b2g4pipe 依赖 Java（推荐 JDK/JRE 11/17）；"
                "请先安装 Java，或按 native/Dockerfile / Apptainer.def 自建容器"
            )
        return path

    def _resolve_binary(self) -> str:
        return self._resolve_java()

    def _resolve_tool(self, name: str) -> str:
        path = base.which(name)
        if not path:
            raise RuntimeError(
                f"未找到 '{name}'：install_blast2goDB.sh 随 local_b2g_db 发行包提供（请设 --db-home）；"
                "mysql 客户端随 MySQL 发行包提供"
            )
        return path

    def _perl(self) -> str:
        return base.which("perl") or "perl"

    def _effective_threads(self, subcommand: str, override: int | None) -> int:
        """线程选择优先级：用户显式 > 子命令建议 > 全局默认（b2g4pipe 单线程，仅契约）。"""
        if override and override > 0:
            return int(override)
        per = (self.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {})
        return int(per.get(subcommand, per.get("default", self.cpus)))

    def _apply_java_opts(self, kw) -> None:
        """--java-opts 覆盖 JAVA_OPTS（Java 工具内存/临时目录透传）。"""
        if kw.get("java_opts"):
            self.env_vars["JAVA_OPTS"] = str(kw["java_opts"])

    def _b2g_dir(self, kw) -> str:
        d = kw.get("b2g_dir") or os.environ.get("B2G4PIPE_HOME")
        if not d:
            raise ValueError(
                "annot 需要 --b2g-dir（b2g4pipe 安装目录）或 B2G4PIPE_HOME 环境变量"
            )
        return os.path.abspath(str(d))

    # -- 命令构建 --------------------------------------------------------- #
    def build_command(self, subcommand: str, **kw) -> list[str]:
        if subcommand not in SUBCOMMANDS:
            raise ValueError(f"未知子命令: {subcommand}（支持 {'/'.join(SUBCOMMANDS)}）")

        self._cwd = None
        self._apply_java_opts(kw)

        if subcommand == "annot":
            return self._build_annot(**kw)
        if subcommand == "install_db":
            return self._build_install_db(**kw)
        return self._build_client(**kw)

    def _build_annot(self, **kw) -> list[str]:
        java = self._resolve_java()
        inp = kw.get("input")
        out = kw.get("out")
        if not inp or not out:
            raise ValueError("annot 需要 -in（BLAST XML，outfmt 5）与 -out（输出前缀）")
        b2g_dir = self._b2g_dir(kw)
        prop = str(kw.get("prop") or (Path(b2g_dir) / "b2gPipe.properties"))

        cmd = [
            java, "-cp", f"{b2g_dir}/*:{b2g_dir}/ext/*", _ANNOT_MAIN,
            "-in", os.path.abspath(str(inp)), "-out", str(out), "-prop", prop,
        ]
        if kw.get("annot", True):
            cmd.append("-annot")
        if kw.get("dat", True):
            cmd.append("-dat")
        if kw.get("annex", True):
            cmd.append("-annex")
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def _build_install_db(self, **kw) -> list[str]:
        db_home = kw.get("db_home")
        if not db_home:
            raise ValueError("install_db 需要 --db-home（含 install_blast2goDB.sh 的本地注释库目录）")
        db_home = os.path.abspath(str(db_home))
        script = Path(db_home) / "install_blast2goDB.sh"
        if not script.exists():
            raise RuntimeError(
                f"未找到 {script}：请先解压 local_b2g_db 发行包到 {db_home}"
                "（含 install_blast2goDB.sh / b2gdb.sql，依赖 MySQL + Perl DBI/DBD::mysql）"
            )
        self._cwd = db_home
        cmd = [self._perl(), str(script)]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def _build_client(self, **kw) -> list[str]:
        home = kw.get("blast2go_home") or os.environ.get("BLAST2GO_HOME")
        if not home:
            raise ValueError("client 需要 --blast2go-home（Blast2GO 安装目录）或 BLAST2GO_HOME 环境变量")
        home = os.path.abspath(str(home))
        launcher = Path(home) / "Blast2GO"
        if not launcher.is_file():
            raise RuntimeError(
                f"未找到 {launcher}：请先用 native/install.sh 安装 Blast2GO 客户端"
                "（许可受限，需注册/订阅获取 Blast2GO_unix_3_3_x64.zip）"
            )
        cmd = [str(launcher)]
        extra = kw.get("extra_args")
        if extra:
            cmd += str(extra).split()
        return cmd

    def run(self, subcommand: str, **kwargs):
        """构建并执行命令（install_db 需在注释库目录内执行）。"""
        args = self.build_command(subcommand, **kwargs)
        return base.run_command(args, env=self.env_vars, cwd=getattr(self, "_cwd", None), check=False)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--threads", type=int, help="覆盖默认线程数（b2g4pipe 单线程，仅契约）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")
    p.add_argument("--java-opts", help="覆盖 JAVA_OPTS（JVM 内存/临时目录，如 \"-Xmx8g\"）")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="blast2go-skill",
        description="blast2go native 技能驱动（Blast2GO 3.3 + b2g4pipe v2.5；需注册/订阅，许可受限）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    pa = sub.add_parser("annot", help=SUBCOMMANDS["annot"])
    pa.add_argument("-in", "--input", dest="input", help="输入 BLAST XML（outfmt 5，如 nr.xml）")
    pa.add_argument("-out", "--out", dest="out", help="输出前缀（生成 <out>.annot / <out>.txt 等）")
    pa.add_argument("--prop", help="b2g4pipe 配置（b2gPipe.properties；默认 <b2g-dir>/b2gPipe.properties）")
    pa.add_argument("--b2g-dir", help="b2g4pipe 安装目录（默认取 B2G4PIPE_HOME）")
    pa.add_argument("--no-annot", dest="annot", action="store_false", help="不输出 -annot")
    pa.add_argument("--no-dat", dest="dat", action="store_false", help="不输出 -dat")
    pa.add_argument("--no-annex", dest="annex", action="store_false", help="不输出 -annex")
    pa.add_argument("--extra-args", help="透传给 B2GAnnotPipe 的额外参数")
    _add_runtime_opts(pa)

    pd = sub.add_parser("install_db", help=SUBCOMMANDS["install_db"])
    pd.add_argument("--db-home", help="本地注释库目录（含 install_blast2goDB.sh）")
    pd.add_argument("--extra-args", help="透传给 install_blast2goDB.sh 的额外参数")
    _add_runtime_opts(pd)

    pc = sub.add_parser("client", help=SUBCOMMANDS["client"])
    pc.add_argument("--blast2go-home", help="Blast2GO 安装目录（默认取 BLAST2GO_HOME）")
    pc.add_argument("--extra-args", help="透传给 Blast2GO 启动器的额外参数")
    _add_runtime_opts(pc)

    return p


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = Blast2GOSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = Blast2GOSkill()
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
