import os
import sys
import argparse
import subprocess
import shlex
from pathlib import Path
import runpy
import shutil
import re


def _strip_ext(path_str: str) -> str:
    base = os.path.basename(path_str)
    for suf in (".bam", ".sam", ".fa", ".fasta", ".bed"):
        if base.endswith(suf):
            return base[: -len(suf)]
    return os.path.splitext(base)[0]


def _default_tama_dir() -> Path:
    return Path(__file__).parent / "gs-tama-1.0.3"


def cmd_run(cmd: str):
    print(f"执行命令:\n{cmd}\n")
    try:
        return subprocess.run(
            cmd,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        print("命令执行失败，捕获到如下输出：")
        if e.stdout:
            print("[stdout]")
            print(e.stdout)
        if e.stderr:
            print("[stderr]")
            print(e.stderr)
        raise


def subcmd_polyacleanup(fasta: str, outdir: str, prefix: str | None, args: str, tama_script: str | None):
    """
    运行 TAMA FLNC polyA 清理（封装自现有 pyflow/tama_polyacleanup.py）
    """
    from tama_polyacleanup import run_tama_polyacleanup

    outputs = run_tama_polyacleanup(
        fasta=fasta,
        output_dir=outdir,
        prefix=prefix,
        args=args,
        tama_script=tama_script,
    )
    print("polyA 清理输出:")
    for k, v in outputs.items():
        print(f"  {k}: {v}")


def _run_tama_script_inprocess(script_path: Path, argv: list[str]):
    """
    使用 runpy 在当前 Python 进程内调用 TAMA 脚本，并提供 xrange 兼容垫片。
    """
    import builtins
    if not hasattr(builtins, "xrange"):
        builtins.xrange = range
    sys.argv = [str(script_path)] + argv
    runpy.run_path(str(script_path), run_name="__main__")


def subcmd_collapse(
    bam: str,
    fasta: str,
    outdir: str,
    prefix: str | None,
    args: str,
    tama_collapse_script: str | None,
    samtools_bin: str | None,
):
    out_path = Path(os.path.abspath(os.path.expanduser(outdir)))
    out_path.mkdir(parents=True, exist_ok=True)

    bam_abs = os.path.abspath(os.path.expanduser(bam))
    fasta_abs = os.path.abspath(os.path.expanduser(fasta))
    if not prefix:
        prefix = _strip_ext(bam_abs)

    # 可选：指定 samtools 路径，优先注入到 PATH，确保 TAMA 内部调用使用该版本
    if samtools_bin:
        sb = os.path.expanduser(samtools_bin)
        if os.path.isfile(sb) and os.access(sb, os.X_OK):
            sam_exec = sb
        else:
            sam_exec = shutil.which(sb) or sb
        sam_dir = os.path.dirname(sam_exec)
        if sam_dir:
            os.environ["PATH"] = f"{sam_dir}:{os.environ.get('PATH', '')}"
        os.environ["SAMTOOLS_BIN"] = sam_exec
        print(f"指定 samtools 路径: {sam_exec}")

    # 解析脚本路径：优先使用仓库内 gs-tama，再回退到 PATH 中的脚本名
    script_path = Path(os.path.expanduser(tama_collapse_script)) if tama_collapse_script else (_default_tama_dir() / "tama_collapse.py")
    use_inprocess = script_path.exists()

    cwd_old = os.getcwd()
    os.chdir(str(out_path))
    try:
        if use_inprocess:
            argv = ["-s", str(bam_abs), "-f", str(fasta_abs), "-p", str(prefix)]
            if args:
                argv += shlex.split(args)
            _run_tama_script_inprocess(script_path, argv)
        else:
            cmd = [
                shutil.which("tama_collapse.py") or "tama_collapse.py",
                "-s", shlex.quote(bam_abs),
                "-f", shlex.quote(fasta_abs),
                "-p", shlex.quote(prefix),
            ]
            if args:
                cmd += shlex.split(args)
            cmd_run(" ".join(cmd))

        # 版本信息写入（与 nf-core/gstama/collapse 一致）
        # 获取版本标记 tc_version_date_...
        version_cmd = f"python3 {script_path} -version | grep 'tc_version_date_' | sed 's/tc_version_date_//g'" if use_inprocess else "tama_collapse.py -version | grep 'tc_version_date_' | sed 's/tc_version_date_//g'"
        ver = subprocess.run(version_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True).stdout.strip() or "unknown"
        with open("versions.yml", "w") as vf:
            vf.write(f"gstama:\n    gstama: {ver}\n")

        print("TAMA collapse 完成，输出目录:", out_path)
    finally:
        os.chdir(cwd_old)


def subcmd_filelist(bed_dir: str, cap: str, order: str, outdir: str, prefix: str | None, pattern: str = "*.bed"):
    out_path = Path(os.path.abspath(os.path.expanduser(outdir)))
    out_path.mkdir(parents=True, exist_ok=True)
    bed_dir_path = Path(os.path.abspath(os.path.expanduser(bed_dir)))

    if not prefix:
        prefix = _strip_ext(str(bed_dir_path))
    tsv_path = out_path / f"{prefix}.tsv"

    # 支持递归匹配：当模式中包含 "**" 时，优先使用 rglob
    if "**" in pattern:
        rpat = pattern
        if pattern.startswith("**/"):
            rpat = pattern[3:]
        elif pattern.startswith("**"):
            # 例如 "**.bed" 的不常见写法，退化为普通后缀匹配
            rpat = pattern.lstrip("*")
        beds = sorted(bed_dir_path.rglob(rpat))
    else:
        beds = sorted(bed_dir_path.glob(pattern))
    # 过滤 macOS 生成的 AppleDouble 伪文件（以 ._ 开头），避免误识别
    beds = [b for b in beds if not b.name.startswith("._")]
    if not beds:
        raise FileNotFoundError(f"在 {bed_dir_path} 下未找到匹配 {pattern} 的 bed 文件")

    with open(tsv_path, "w") as f:
        for bed in beds:
            m = re.search(r"chunk(\d+)", bed.name)
            if m:
                n = m.group(1)
                order_str = f"{n},{n},{n}"
            elif order:
                o = str(order).strip()
                if "," in o:
                    parts = [p.strip() for p in o.split(",")]
                    if len(parts) == 3 and all(p.isdigit() for p in parts):
                        order_str = ",".join(parts)
                    else:
                        order_str = "1,1,1"
                elif o.isdigit():
                    order_str = f"{o},{o},{o}"
                else:
                    order_str = "1,1,1"
            else:
                order_str = "1,1,1"
            # 将第4列设为来源标签且保持唯一性：<source>:<sample>:<file_tag>
            # 其中 <source> 来自 --bed-dir 的目录名（如 minimap2/ultra），<sample> 为上级目录名，<file_tag> 为去掉扩展的文件名（可包含 chunk 信息）
            source_label = bed_dir_path.name
            sample_label = bed.parent.name
            file_tag = bed.stem
            source_id = f"{source_label}:{sample_label}:{file_tag}"
            f.write(f"{bed}\t{cap}\t{order_str}\t{source_id}\n")

    # 版本信息，参考 nf-core 模块（在 macOS 可能获取不到 echo 版本，降级为 unknown）
    try:
        ver = subprocess.run("echo --version | sed -e 's/echo (GNU coreutils) //'", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True).stdout.strip() or "unknown"
    except Exception:
        ver = "unknown"
    with open(out_path / "versions.yml", "w") as vf:
        vf.write(f"GSTAMA_FILELIST:\n    echo: {ver}\n")

    print(f"生成 filelist: {tsv_path}，包含 {len(beds)} 个条目")
    return str(tsv_path)


def subcmd_merge(filelist: str, outdir: str, prefix: str | None, args: str, tama_merge_script: str | None):
    out_path = Path(os.path.abspath(os.path.expanduser(outdir)))
    out_path.mkdir(parents=True, exist_ok=True)

    filelist_abs = os.path.abspath(os.path.expanduser(filelist))
    # Guard: skip merge when filelist is missing or empty (e.g., collapse produced no BED)
    if not os.path.exists(filelist_abs):
        print(f"[WARN] 未找到 filelist: {filelist_abs}，跳过 merge。")
        with open(out_path / "versions.yml", "w") as vf:
            vf.write("gstama_merge:\n    gstama: skipped (no filelist)\n")
        return
    try:
        with open(filelist_abs, "r", encoding="utf-8") as f:
            has_content = any(line.strip() for line in f)
    except Exception:
        has_content = False
    if not has_content:
        print(f"[WARN] filelist 为空（collapse 未产出 bed），跳过 merge：{filelist_abs}")
        with open(out_path / "versions.yml", "w") as vf:
            vf.write("gstama_merge:\n    gstama: skipped (empty filelist)\n")
        return
    if not prefix:
        prefix = _strip_ext(filelist_abs)

    script_path = Path(os.path.expanduser(tama_merge_script)) if tama_merge_script else (_default_tama_dir() / "tama_merge.py")
    use_inprocess = script_path.exists()

    cwd_old = os.getcwd()
    os.chdir(str(out_path))
    try:
        if use_inprocess:
            argv = ["-f", str(filelist_abs), "-d", "merge_dup", "-p", str(prefix)]
            if args:
                argv += shlex.split(args)
            _run_tama_script_inprocess(script_path, argv)
        else:
            cmd = [
                shutil.which("tama_merge.py") or "tama_merge.py",
                "-f", shlex.quote(filelist_abs),
                "-d", "merge_dup",
                "-p", shlex.quote(prefix),
            ]
            if args:
                cmd += shlex.split(args)
            cmd_run(" ".join(cmd))

        # 版本信息（与 nf-core/gstama/merge 一致）
        version_cmd = f"python3 {script_path} -version | head -n1" if use_inprocess else "tama_merge.py -version | head -n1"
        ver = subprocess.run(version_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True).stdout.strip() or "unknown"
        with open("versions.yml", "w") as vf:
            vf.write(f"gstama_merge:\n    gstama: {ver}\n")

        print("TAMA merge 完成，输出目录:", out_path)
    finally:
        os.chdir(cwd_old)


def main():
    parser = argparse.ArgumentParser(description="gs-TAMA 封装：polyacleanup / collapse / filelist / merge")
    subparsers = parser.add_subparsers(dest="subcmd", required=True)

    # polyacleanup
    p_poly = subparsers.add_parser("polyacleanup", help="运行 TAMA FLNC polyA 清理")
    p_poly.add_argument("--fasta", required=True, help="输入 FLNC FASTA 文件（例如 BamTools convert 的输出）")
    p_poly.add_argument("--outdir", required=True, help="输出目录")
    p_poly.add_argument("--prefix", default=None, help="输出前缀（默认在输入文件名基础上追加 _tama）")
    p_poly.add_argument("--args", default="", nargs='?', help="透传给 TAMA 清理脚本的附加参数（可选）")
    p_poly.add_argument("--tama-script", default=None, help="tama_flnc_polya_cleanup.py 的绝对路径（默认使用仓库内路径）")

    # collapse
    p_col = subparsers.add_parser("collapse", help="运行 TAMA collapse 进行转录本去冗余")
    p_col.add_argument("--bam", required=True, help="输入对齐后的 BAM 或 SAM 文件（建议 BAM 且已排序）")
    p_col.add_argument("--fasta", required=True, help="参考基因组 FASTA")
    p_col.add_argument("--outdir", required=True, help="输出目录")
    p_col.add_argument("--prefix", default=None, help="输出前缀（默认从 BAM 文件名推断）")
    p_col.add_argument("--args", default="", nargs='?', help="透传给 tama_collapse.py 的附加参数（可选）")
    p_col.add_argument("--tama-collapse-script", default=None, help="tama_collapse.py 的绝对路径（默认使用仓库内路径）")
    p_col.add_argument("--samtools-bin", default=None, help="samtools 可执行路径")

    # filelist
    p_fl = subparsers.add_parser("filelist", help="根据 collapse 产出的 bed 列表生成合并所需 TSV")
    p_fl.add_argument("--bed-dir", required=True, help="包含多个 *.bed 的目录（collapse 输出）")
    p_fl.add_argument("--cap", choices=("capped", "no_cap"), default="no_cap", help="是否为 capped，仅支持 'capped' 或 'no_cap'（Iso-Seq 默认 no_cap）")
    p_fl.add_argument("--order", default=None, help="来源优先级（三元 'start,junction,end'）。当文件名含 'chunk<N>' 时自动生成 '<N>,<N>,<N>'；否则使用此值或默认 '1,1,1'。")
    p_fl.add_argument("--outdir", required=True, help="输出目录")
    p_fl.add_argument("--prefix", default=None, help="filelist 前缀（默认取 bed 目录名）")
    p_fl.add_argument("--pattern", default="*.bed", help="bed 文件通配模式（默认 *.bed）")

    # merge
    p_mg = subparsers.add_parser("merge", help="运行 TAMA merge 合并多个转录本集合")
    p_mg.add_argument("--filelist", required=True, help="由 filelist 子命令生成的 TSV 文件")
    p_mg.add_argument("--outdir", required=True, help="输出目录")
    p_mg.add_argument("--prefix", default=None, help="输出前缀（默认从 filelist 文件名推断）")
    p_mg.add_argument("--args", default="", nargs='?', help="透传给 tama_merge.py 的附加参数（可选）")
    p_mg.add_argument("--tama-merge-script", default=None, help="tama_merge.py 的绝对路径（默认使用仓库内路径）")

    ns = parser.parse_args()

    if ns.subcmd == "polyacleanup":
        subcmd_polyacleanup(ns.fasta, ns.outdir, ns.prefix, ns.args, ns.tama_script)
    elif ns.subcmd == "collapse":
        # 延迟导入避免在非使用情况下的依赖
        import shutil  # noqa: F401
        subcmd_collapse(ns.bam, ns.fasta, ns.outdir, ns.prefix, ns.args, ns.tama_collapse_script, ns.samtools_bin)
    elif ns.subcmd == "filelist":
        subcmd_filelist(ns.bed_dir, ns.cap, ns.order, ns.outdir, ns.prefix, ns.pattern)
    elif ns.subcmd == "merge":
        import shutil  # noqa: F401
        subcmd_merge(ns.filelist, ns.outdir, ns.prefix, ns.args, ns.tama_merge_script)


if __name__ == "__main__":
    main()