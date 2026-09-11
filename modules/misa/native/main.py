#!/usr/bin/env python3
"""misa（MISA v2.1，misa.pl）native 标准入口驱动。

CLI 直跑（人类 / Shell）：
    # 默认参数（misa.ini 由驱动生成：definition 1-10 2-6 3-5 4-5 5-5 6-5 / interruptions 100 / GFF false）
    python main.py detect genome.fasta --outdir misa_out
    # 自带 misa.ini（misa.pl 只从当前工作目录读 misa.ini，驱动负责把它落到 --outdir）
    python main.py detect genome.fasta --outdir misa_out --ini my.misa.ini
    # 逐序列 GFF3（⚠️ 与 .misa 互斥：开启后不再产出 .misa，下游 misa_primer3.pl 需要 .misa）
    python main.py detect genome.fasta --outdir misa_out --gff

Agent Function Calling / Schema 自省：
    python main.py --schema          # 打印 JSON Schema
    python main.py --list-commands   # 列出支持的子命令

等价于教学命令 `misa.pl genome.fasta`：misa.pl 把 <ARGV[0]>.misa / <ARGV[0]>.statistics 写在
「传入路径」旁、把逐序列 <序列 ID>.gff 写在**当前工作目录**（且只从 cwd 读 misa.ini）。驱动因此
统一在 --outdir 内：写 misa.ini → 建立指向输入 FASTA 的同名软链 → 以 cwd=outdir + 相对文件名
调用 misa.pl，使全部产物落在 --outdir，且不向输入 FASTA 所在目录写任何文件。

产物互斥（v2.1 实测，2026-09）：misa.ini 的 GFF: true → misa.pl 只写逐序列 <序列 ID>.gff，
**不写 .misa**（misa_primer3.pl / p3_in.pl 等下游需要 .misa，故驱动默认 GFF false）。

SSR 侧翼引物设计（misa_primer3.pl + primer3_core）见 subworkflow/misa_primer3。
"""
from __future__ import annotations

import argparse
import json
import os
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
    "detect": "包装 misa.pl：FASTA（+ misa.ini）→ <fasta>.misa / <fasta>.statistics（或 --gff 时逐序列 <序列 ID>.gff）",
}

# misa.ini 固定文件名（misa.pl 无命令行参数，只从当前工作目录读该文件）
INI_NAME = "misa.ini"

# 官方 v2.1 默认搜索参数（生成 ini 时使用）
DEFAULT_MIN_REPEATS = "1-10 2-6 3-5 4-5 5-5 6-5"
DEFAULT_INTERRUPTIONS = 100


class MisaSkill(base.SkillBase):
    software = "misa"
    binary = "misa.pl"

    # ------------------------------------------------------------------ #
    # 参数 → 命令
    # ------------------------------------------------------------------ #
    def default_ini(self, min_repeats=None, interruptions=None, gff=False) -> str:
        """按官方 v2.1 默认生成 misa.ini 文本（def / int / GFF 三行）。"""
        spec = str(min_repeats or DEFAULT_MIN_REPEATS).strip()
        try:
            amb = int(DEFAULT_INTERRUPTIONS if interruptions is None else interruptions)
        except (TypeError, ValueError) as exc:
            raise RuntimeError("--interruptions 需为整数") from exc
        if amb < 0:
            raise RuntimeError(f"--interruptions 需 >= 0（收到 {amb}）")
        return (
            f"definition(unit_size,min_repeats):           {spec}\n"
            f"interruptions(max_difference_for_2_SSRs):    {amb}\n"
            f"GFF:                                        {'true' if gff else 'false'}\n"
        )

    def prepare(self, *, fasta, outdir=None, ini=None, min_repeats=None,
                interruptions=None, gff=False, **_ignored):
        """准备运行环境：校验输入、落 misa.ini、在 outdir 内建输入软链。

        返回 (输入真实路径, outdir, ini 路径, 软链路径)；供 build_command/run 共用，
        保证「以 cwd=outdir + 相对文件名」调用 misa.pl 时产物全部落在 outdir。
        """
        raw = Path(str(fasta)).expanduser()
        if not raw.is_file():
            raise RuntimeError(f"输入 FASTA 不存在: {raw}")
        real = raw.resolve()

        outdir_path = Path(str(outdir or ".")).expanduser()
        try:
            outdir_path.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise RuntimeError(f"无法创建输出目录 {outdir_path}: {exc}") from exc
        outdir_path = outdir_path.resolve()

        # 1) misa.ini（misa.pl 只从 cwd 读；未给 --ini 时按参数生成）
        if ini:
            ini_src = Path(str(ini)).expanduser()
            if not ini_src.is_file():
                raise RuntimeError(f"misa.ini 不存在: {ini_src}")
            ini_text = ini_src.read_text(encoding="utf-8")
        else:
            ini_text = self.default_ini(min_repeats, interruptions, gff)
        ini_path = outdir_path / INI_NAME
        if ini_path.exists():
            if ini_path.read_text(encoding="utf-8") != ini_text:
                raise RuntimeError(
                    f"{ini_path} 已存在且内容与本次参数不同；请改用 --outdir 指定其它目录，"
                    "或让 --ini/--min-repeats/--interruptions/--gff 与该文件内容一致"
                )
        else:
            ini_path.write_text(ini_text, encoding="utf-8")

        # 2) 输入软链（misa.pl 以 <ARGV[0]>.misa 命名产物，故以原名软链到 outdir 内运行）
        link = outdir_path / raw.name
        if link.exists() and os.path.samefile(link, real):
            pass  # outdir 内就是同一文件（例如就地运行）
        elif link.is_symlink() and not link.exists():
            link.unlink()
            link.symlink_to(real)
        elif link.exists():
            raise RuntimeError(
                f"{link} 已存在且不是本次输入（{real}）；请改用 --outdir 指定其它目录或重命名输入文件"
            )
        else:
            link.symlink_to(real)
        return real, outdir_path, ini_path, link

    def build_command(self, subcommand: str, **kw) -> list[str]:
        """构建 misa.pl 命令行（相对文件名；cwd 由 run() 设为 outdir）。"""
        if subcommand != "detect":
            raise RuntimeError(f"未知子命令: {subcommand}")
        binary = self._resolve_binary()
        fasta = kw.get("fasta")
        if not fasta:
            raise RuntimeError("detect 需要输入 FASTA（positional / --input）")
        if kw.get("ini") and kw.get("gff"):
            raise RuntimeError("--ini 与 --gff 不能同时提供（--ini 已自带 GFF 设置）")
        return [binary, Path(str(fasta)).expanduser().name]

    def run(self, subcommand: str, **kwargs) -> base.RunResult:
        """构建命令 → 准备 outdir（misa.ini + 输入软链）→ 以 cwd=outdir 执行 misa.pl。"""
        args = self.build_command(subcommand, **kwargs)
        _real, outdir_path, _ini_path, _link = self.prepare(**kwargs)
        run_env = os.environ.copy()
        run_env.update(self.env_vars)
        try:
            proc = subprocess.run(
                args,
                cwd=str(outdir_path),
                env=run_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
        except FileNotFoundError as exc:
            raise RuntimeError(f"可执行文件未找到: {args[0]}") from exc
        result = base.RunResult(
            command=args, returncode=proc.returncode,
            stdout=proc.stdout or "", stderr=proc.stderr or "",
        )
        if not result.ok:
            raise RuntimeError(
                f"命令执行失败 (code={result.returncode}): {' '.join(args)}\n"
                f"stderr:\n{result.stderr}"
            )
        return result


# --------------------------------------------------------------------------- #
# 产物报告
# --------------------------------------------------------------------------- #
def _gff_set(outdir: str | Path) -> set[Path]:
    return set(Path(outdir).glob("*.gff"))


def _ini_gff(ini_path: Path) -> bool:
    """读 outdir/misa.ini 判定是否开了 GFF（misa.pl 的判据：^GFF\\S*\\s+true）。"""
    if not ini_path.is_file():
        return False
    for line in ini_path.read_text(encoding="utf-8").splitlines():
        if line.lower().startswith("gff") and " true" in line.lower():
            return True
    return False


def _report(outdir: str | Path, fasta_name: str, gff: bool,
            new_gff: set[Path]) -> list[str]:
    """汇总本次 detect 的产物路径（.misa 记录数 / .statistics / 新增 .gff）。"""
    out = Path(outdir)
    lines: list[str] = []
    misa_file = out / f"{fasta_name}.misa"
    stats_file = out / f"{fasta_name}.statistics"
    if misa_file.is_file():
        with misa_file.open(encoding="utf-8") as fh:
            n = max(sum(1 for _ in fh) - 1, 0)  # 去掉表头
        lines.append(f"  {misa_file}（SSR 记录 {n} 条）")
    elif gff:
        lines.append(
            f"  [NOTE] misa.ini 为 GFF: true → 未产出 {misa_file.name}"
            "（.misa 与 GFF 输出互斥）；下游 misa_primer3.pl 需要 .misa，请改用 GFF: false"
        )
    if stats_file.is_file():
        lines.append(f"  {stats_file}")
    if new_gff:
        lines.append("  " + "、".join(str(p) for p in sorted(new_gff)))
    elif gff:
        lines.append("  [NOTE] 未生成 .gff（序列中可能没有满足阈值的 SSR）")
    return lines


def _emit_stderr(text: str) -> None:
    """输出 misa.pl stderr：已知的 perl 遗留正则告警折叠为一条 NOTE。"""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return
    benign = [ln for ln in lines if "Unescaped left brace in regex" in ln]
    if benign:
        print(
            f"[NOTE] misa.pl 触发 perl 遗留正则告警 {len(benign)} 条"
            "（Unescaped left brace in regex；上游 v2.1 正则中含 {n.m} 形式，"
            "属已知告警，不影响 SSR 检测结果）",
            file=sys.stderr,
        )
    for ln in lines:
        if "Unescaped left brace in regex" not in ln:
            print(ln, file=sys.stderr)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="misa-skill",
        description="misa（MISA v2.1 misa.pl）native 技能驱动（FASTA → SSR 位点表 / 统计 / GFF3）",
    )
    p.add_argument("--schema", action="store_true", help="输出 JSON Schema 后退出")
    p.add_argument("--list-commands", action="store_true", help="列出支持的子命令")
    sub = p.add_subparsers(dest="subcommand", metavar="<subcommand>")

    # detect: misa.pl <fasta>（cwd=outdir，misa.ini 由驱动准备）
    pd = sub.add_parser("detect", help=SUBCOMMANDS["detect"])
    pd.add_argument("fasta", nargs="?", help="输入 FASTA（单文件可含多条序列；等价 --input）")
    pd.add_argument("--input", dest="fasta", help="同上：输入 FASTA 路径（与 positional 二选一）")
    pd.add_argument("--outdir", default=".", help="输出目录（默认当前目录；产物 .misa/.statistics/.gff 全落在其中）")
    pd.add_argument("--ini", help="自定义 misa.ini（与 --gff 互斥；未给时按下方参数生成）")
    pd.add_argument("--min-repeats", dest="min_repeats", default=DEFAULT_MIN_REPEATS,
                    help=f"definition(unit_size,min_repeats)（默认官方 v2.1：{DEFAULT_MIN_REPEATS}）")
    pd.add_argument("--interruptions", type=int, default=DEFAULT_INTERRUPTIONS,
                    help=f"复合 SSR 两个 SSR 之间允许的最大碱基数（默认 {DEFAULT_INTERRUPTIONS}）")
    pd.add_argument("--gff", action="store_true",
                    help="生成 misa.ini 时写 GFF: true（逐序列 .gff；⚠️ 与 .misa 输出互斥）")
    _add_runtime_opts(pd)

    return p


def _add_runtime_opts(p: argparse.ArgumentParser) -> None:
    """为每个子命令附加运行期覆盖项（线程/临时目录）。"""
    p.add_argument("--threads", type=int, help="覆盖默认线程数（协议位：misa.pl 单线程，不强加）")
    p.add_argument("--tmpdir", help="覆盖默认临时目录")


def main(argv: list[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]

    # 先拦截自省命令（不依赖子命令）
    if "--list-commands" in args:
        for k, v in SUBCOMMANDS.items():
            print(f"{k:12s} {v}")
        return 0
    if "--schema" in args:
        skill = MisaSkill()
        print(json.dumps(skill.schema(), indent=2, ensure_ascii=False))
        return 0

    ns = build_parser().parse_args(args)
    if not ns.subcommand:
        build_parser().print_help(sys.stderr)
        return 2

    skill = MisaSkill()
    if getattr(ns, "tmpdir", None):
        skill.tmpdir = ns.tmpdir
        skill.env_vars["TMPDIR"] = ns.tmpdir

    kw = {k: v for k, v in vars(ns).items()
          if k not in ("subcommand", "threads", "tmpdir") and v is not None}
    kw["threads"] = ns.threads

    if not kw.get("fasta"):
        print("[ERROR] detect 需要输入 FASTA（positional / --input）", file=sys.stderr)
        return 1

    outdir = kw.get("outdir") or "."
    before_gff = _gff_set(outdir) if Path(outdir).is_dir() else set()
    try:
        result = skill.run(ns.subcommand, **kw)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    fasta_name = Path(str(kw["fasta"])).expanduser().name
    gff_on = _ini_gff(Path(outdir) / INI_NAME)
    print(f"# misa detect 完成（misa.pl，GFF={'true' if gff_on else 'false'}）")
    for line in _report(outdir, fasta_name, gff_on, _gff_set(outdir) - before_gff):
        print(line)
    if result.stdout.strip():
        print(result.stdout.strip())
    _emit_stderr(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
