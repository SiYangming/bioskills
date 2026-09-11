#!/usr/bin/env python3
"""misa_primer3（MISA + Primer3 SSR 检测与引物设计）组合流程编排入口。

三个 stage（--list-stages 可查）：

  1) misa_detect            modules/misa/native/main.py detect  → <outdir>/misa/<genome>.misa（+ .statistics）
  2) prepare_p3_settings    由 native/p3_settings.txt 生成 Primer3 设置文件（去注释/空行 +
                            PRIMER_THERMODYNAMIC_PARAMETERS_PATH 指向真实 primer3_config，或删行回退内置默认）
  3) misa_primer3_design    native/misa_primer3.pl（--CPU N 经 ParaFly 并行调用 primer3_core）
                            → <outdir>/misa_primer3.out（TSV）+ <outdir>/misa_primer3.gff3

用法（仓库根执行）：
  python subworkflow/misa_primer3/native/main.py --list-stages
  python subworkflow/misa_primer3/native/main.py --dry-run --genome genome.fasta          # 默认即 dry-run
  python subworkflow/misa_primer3/native/main.py --real --genome genome.fasta --outdir results --threads 8

依赖（--real 时）：primer3_core（modules/primer3 环境）+ ParaFly（--CPU 并行）+ perl（misa_primer3.pl）；
misa.pl 由 modules/misa 提供。详见同目录 misa_primer3.md「环境准备」。

⚠️ MISA 的 .misa 与 GFF 输出互斥：本流程的 detect stage 固定 GFF: false（否则拿不到下游需要的 .misa），
   最终 GFF3 由 design stage 的 --gff3_out 产出。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parent.parent.parent          # 仓库根
_MODULES = _REPO_ROOT / "modules"
MISA_MAIN = _MODULES / "misa" / "native" / "main.py"
MISA_PRIMER3_PL = _HERE / "misa_primer3.pl"
P3_TEMPLATE = _HERE / "p3_settings.txt"

STAGES = [
    "misa_detect",
    "prepare_p3_settings",
    "misa_primer3_design",
]

# --------------------------------------------------------------------------- #
# 工具解析 / Primer3 设置文件准备
# --------------------------------------------------------------------------- #
def resolve_primer3_config(primer3_core: str | None = None) -> Path | None:
    """定位 primer3_config 目录（PRIMER_THERMODYNAMIC_PARAMETERS_PATH 指向它）。找不到返回 None。"""
    cands: list[Path] = []
    bin_path = primer3_core or shutil.which("primer3_core")
    if bin_path:
        b = Path(bin_path).resolve()
        cands += [
            b.parent / "primer3_config",
            b.parent.parent / "share" / "primer3" / "primer3_config",
            b.parent.parent / "share" / "primer3_config",
            b.parent.parent / "primer3_config",
        ]
    for env in ("CONDA_PREFIX", "PREFIX"):
        prefix = os.environ.get(env)
        if prefix:
            cands += [
                Path(prefix) / "share" / "primer3" / "primer3_config",
                Path(prefix) / "share" / "primer3_config",
            ]
    cands += [Path("/usr/local/share/primer3/primer3_config"),
              Path("/usr/share/primer3/primer3_config")]
    for cand in cands:
        if cand.is_dir():
            return cand
    return None


def prepare_p3_settings(template: str | Path, out_path: str | Path,
                        thermo_dir: str | Path | None = None) -> dict:
    """由 Primer3 设置模板生成可用的设置文件。

    等价教学链路的两条 perl 单行命令：
      perl -p -e 's/\\s*#.*//; s/^\\s*$//; s/P3_FILE_ID/\\nP3_FILE_ID/' p3_settings.txt > p3_settings_file
      perl -p -i -e 's#^PRIMER_THERMODYNAMIC_PARAMETERS_PATH.*#PRIMER_THERMODYNAMIC_PARAMETERS_PATH=<配置目录>/#' p3_settings_file

    区别：热力学参数目录由调用方探测（thermo_dir）；探测不到时**删除**该行（primer3_core 回退编译内置
    默认参数），而不是留一个不存在的路径 —— 否则 primer3_core 会直接
    `PRIMER_ERROR=Unable to open file .../dangle.dh` 失败（2026-09 实测）。
    """
    src = Path(template)
    if not src.is_file():
        raise RuntimeError(f"Primer3 设置模板不存在: {src}")

    lines: list[str] = []
    for raw in src.read_text(encoding="utf-8").splitlines():
        line = re.sub(r"\s*#.*$", "", raw)      # 去注释（整行注释会变为空串）
        if not line.strip():                    # 去空行
            continue
        if line.startswith("P3_FILE_ID") and lines and lines[-1].strip():
            lines.append("")                    # 复刻 s/P3_FILE_ID/\nP3_FILE_ID/：设置头与 ID 之间留空行
        lines.append(line)

    out_lines: list[str] = []
    thermo_state = "not-present"
    for line in lines:
        if line.startswith("PRIMER_THERMODYNAMIC_PARAMETERS_PATH"):
            if thermo_dir:
                out_lines.append(
                    "PRIMER_THERMODYNAMIC_PARAMETERS_PATH="
                    f"{Path(thermo_dir).as_posix().rstrip('/')}/"
                )
                thermo_state = "set"
            else:
                thermo_state = "dropped"
            continue
        out_lines.append(line)

    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    return {
        "path": str(out),
        "lines": len(out_lines),
        "thermodynamic_path": thermo_state,
        "thermodynamic_dir": str(thermo_dir) if thermo_state == "set" else None,
    }


# --------------------------------------------------------------------------- #
# stage 命令构造
# --------------------------------------------------------------------------- #
def misa_detect_cmd(genome: str | Path, misa_outdir: str | Path,
                    ini: str | None = None, misa_main: Path | None = None) -> list[str]:
    main_py = MISA_MAIN if misa_main is None else misa_main
    cmd = [sys.executable, str(main_py), "detect", str(genome), "--outdir", str(misa_outdir)]
    if ini:
        cmd += ["--ini", str(ini)]
    return cmd


def design_cmd(misa_file: str | Path, genome: str | Path, p3_file: str | Path,
               cpu: int, flanking: int, product_min: int, product_max: int,
               gff3_out: str | Path | None = None,
               script: Path | None = None) -> list[str]:
    pl = MISA_PRIMER3_PL if script is None else script
    cmd = [
        "perl", str(pl),
        "--CPU", str(cpu),
        "--flanking_length", str(flanking),
        "--min_product_length", str(product_min),
        "--max_product_length", str(product_max),
    ]
    if gff3_out:
        cmd += ["--gff3_out", str(gff3_out)]
    # ⚠️ --p3_setting_file 必须带选项名（usage: misa_primer3.pl <misa> <fasta>，第 3 个位置参数会被当 FASTA）
    cmd += ["--p3_setting_file", str(p3_file), str(misa_file), str(genome)]
    return cmd


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
def run_pipeline(args) -> int:
    real = bool(args.real)
    # 全部路径解析为绝对路径：stage 3 以 cwd=<outdir>/misa_primer3 运行，相对路径会解析错位
    outdir = Path(args.outdir).expanduser().resolve()
    genome = Path(args.genome).expanduser().resolve()
    misa_outdir = outdir / "misa"
    misa_file = misa_outdir / f"{genome.name}.misa"
    design_workdir = outdir / "misa_primer3"
    p3_file = (Path(args.p3_setting_file).expanduser().resolve() if args.p3_setting_file
               else outdir / "p3_settings_file")
    gff3_out = None if args.no_gff3 else (Path(args.gff3_out).expanduser().resolve()
                                          if args.gff3_out else outdir / "misa_primer3.gff3")
    out_tsv = outdir / "misa_primer3.out"

    print(f"# custom_misa_primer3 ({'real' if real else 'dry-run'}) genome={genome}")
    print(f"# outdir={outdir} threads(CPU)={args.threads}")

    # ---------------- stage 1: MISA SSR 检测 ----------------
    detect = misa_detect_cmd(genome, misa_outdir, args.misa_ini)
    print("[misa_detect] " + " ".join(map(str, detect)))
    if real:
        if not MISA_MAIN.is_file():
            print(f"[ERROR] 未找到 misa native 入口 {MISA_MAIN}（请先按 modules/misa/README.md 构建）",
                  file=sys.stderr)
            return 1
        outdir.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(detect, check=False)
        if proc.returncode != 0:
            print(f"[ERROR] misa_detect 失败（exit {proc.returncode}）", file=sys.stderr)
            return proc.returncode
        if not misa_file.is_file():
            print(f"[ERROR] misa_detect 未产出预期文件 {misa_file}", file=sys.stderr)
            return 1

    # ---------------- stage 2: 准备 Primer3 设置文件 ----------------
    if args.p3_setting_file:
        p3_src = p3_file
        print(f"[prepare_p3_settings] 使用用户提供的设置文件: {p3_src}")
        if real and not p3_src.is_file():
            print(f"[ERROR] --p3-setting-file 不存在: {p3_src}", file=sys.stderr)
            return 1
        thermo_dir = None
    else:
        thermo_dir = resolve_primer3_config()
        print(f"[prepare_p3_settings] {P3_TEMPLATE} -> {p3_file}"
              f"（primer3_config: {thermo_dir if thermo_dir else '未找到 → 删除 PRIMER_THERMODYNAMIC_PARAMETERS_PATH 行'}）")
        if real:
            info = prepare_p3_settings(P3_TEMPLATE, p3_file, thermo_dir)
            print(f"  {info['lines']} 行；thermodynamic_path={info['thermodynamic_path']}"
                  + (f"（{info['thermodynamic_dir']}）" if info["thermodynamic_dir"] else ""))
            if info["thermodynamic_path"] == "dropped":
                print("  [WARN] 未找到 primer3_config，设置文件中已删除 "
                      "PRIMER_THERMODYNAMIC_PARAMETERS_PATH（primer3_core 将用编译内置默认参数）",
                      file=sys.stderr)

    # ---------------- stage 3: misa_primer3.pl 批量设计引物 ----------------
    design = design_cmd(misa_file, genome, p3_file, args.threads,
                        args.flanking_length, args.product_min, args.product_max,
                        gff3_out)
    print(f"[misa_primer3_design] (cwd={design_workdir}) " + " ".join(map(str, design))
          + f" > {out_tsv}")
    if not real:
        print("# dry-run 结束（加 --real 真实执行；需 primer3_core + ParaFly 在 PATH）")
        return 0

    if shutil.which("perl") is None:
        print("[ERROR] 未找到 perl（misa_primer3.pl 为 Perl 脚本）", file=sys.stderr)
        return 1
    if shutil.which("primer3_core") is None:
        print("[ERROR] 未找到 primer3_core（请按 modules/primer3/README.md「环境安装」安装）",
              file=sys.stderr)
        return 1
    if shutil.which("ParaFly") is None:
        print("[ERROR] 未找到 ParaFly（misa_primer3.pl 经 ParaFly 实现 --CPU 并行；"
              "mamba install -c bioconda parafly）", file=sys.stderr)
        return 1
    if not MISA_PRIMER3_PL.is_file():
        print(f"[ERROR] 未找到 {MISA_PRIMER3_PL}", file=sys.stderr)
        return 1

    # misa_primer3.pl 在 cwd 下写 misa_primer3.commands 与 misa_primer3.tmp/ → 每次运行前清理，保证确定性
    design_workdir.mkdir(parents=True, exist_ok=True)
    for stale in ("misa_primer3.tmp", "misa_primer3.commands"):
        target = design_workdir / stale
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()

    try:
        with open(out_tsv, "w", encoding="utf-8") as fh:
            proc = subprocess.run(design, cwd=str(design_workdir), stdout=fh, check=False)
    except OSError as exc:
        print(f"[ERROR] 执行 misa_primer3.pl 失败: {exc}", file=sys.stderr)
        return 1
    if proc.returncode != 0:
        print(f"[ERROR] misa_primer3_design 失败（exit {proc.returncode}）；"
              f"中间产物见 {design_workdir}/misa_primer3.tmp/", file=sys.stderr)
        return proc.returncode

    recs = max(sum(1 for _ in out_tsv.open(encoding="utf-8")) - 1, 0)
    print(f"[misa_primer3_design] 完成：{out_tsv}（{recs} 条 SSR 记录）")
    if gff3_out and Path(gff3_out).is_file():
        print(f"  GFF3: {gff3_out}")
    print(f"  中间产物: {design_workdir}/misa_primer3.tmp/（每位点 settings 与 primer3_core 输出）")
    print(f"  MISA 位点表: {misa_file}；统计: {misa_outdir / (genome.name + '.statistics')}")
    return 0


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="subworkflow/misa_primer3 — MISA SSR 检测 + Primer3 侧翼引物设计组合流程")
    p.add_argument("--genome", required=False, help="输入基因组/序列 FASTA（--real/--dry-run 必填）")
    p.add_argument("--outdir", default="results", help="输出目录（默认 results）")
    p.add_argument("--threads", "--cpu", dest="threads", type=int, default=8,
                   help="并行数（透传 misa_primer3.pl 的 --CPU，经 ParaFly；默认 8）")
    p.add_argument("--p3-setting-file", dest="p3_setting_file",
                   help="Primer3 设置文件；未给时由 native/p3_settings.txt 自动生成到 <outdir>/p3_settings_file")
    p.add_argument("--gff3-out", dest="gff3_out", help="GFF3 输出路径（默认 <outdir>/misa_primer3.gff3）")
    p.add_argument("--no-gff3", action="store_true", help="不输出 GFF3")
    p.add_argument("--misa-ini", dest="misa_ini", help="透传 modules/misa detect 的 --ini（自定义 misa.ini）")
    p.add_argument("--flanking-length", dest="flanking_length", type=int, default=300,
                   help="提取 SSR 两侧翼长度（misa_primer3.pl 默认 300）")
    p.add_argument("--min-product-length", dest="product_min", type=int, default=100,
                   help="引物最小产物长度（默认 100）")
    p.add_argument("--max-product-length", dest="product_max", type=int, default=250,
                   help="引物最大产物长度（默认 250）")
    p.add_argument("--dry-run", action="store_true",
                   help="仅打印 stage 命令（不加任何模式参数时的默认行为；与 --real 互斥）")
    p.add_argument("--real", action="store_true", help="真实执行各 stage（需 misa/primer3/parafly 就绪）")
    return p


def main(argv=None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]
    # 行缓冲：stdout 与 stderr 混排（重定向到文件时）保持可读顺序
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except (AttributeError, ValueError):
        pass

    # 先拦截自省命令（不依赖必填参数）
    if "--list-stages" in argv:
        print(json.dumps({
            "id": "custom_misa_primer3",
            "stages": STAGES,
            "summary": "MISA 检测 SSR → 准备 Primer3 设置 → misa_primer3.pl 批量设计侧翼引物（TSV + GFF3）",
        }, ensure_ascii=False, indent=2))
        return 0

    args = build_parser().parse_args(argv)
    if args.dry_run and args.real:
        print("[ERROR] --dry-run 与 --real 互斥（默认即 dry-run）", file=sys.stderr)
        return 2
    if not args.genome:
        print("[ERROR] 需要 --genome <FASTA>（--help 查看用法）", file=sys.stderr)
        return 1
    return run_pipeline(args)


if __name__ == "__main__":
    raise SystemExit(main())
