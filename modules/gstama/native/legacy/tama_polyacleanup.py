import os
import sys
import argparse
import subprocess
import shutil
import runpy
from pathlib import Path
import shlex


def _default_tama_script_path() -> Path:
    here = Path(__file__).parent
    return here / "gs-tama-1.0.3" / "tama_go" / "sequence_cleanup" / "tama_flnc_polya_cleanup.py"


def _derive_prefix_from_fasta(fasta_path: str) -> str:
    stem = Path(fasta_path).stem
    if not stem.endswith("_tama"):
        stem = stem + "_tama"
    return stem


def run_tama_polyacleanup(
    fasta: str,
    output_dir: str,
    prefix: str = None,
    args: str = "",
    tama_script: str = None,
):
    """
    调用 TAMA 的 FLNC polyA 清理脚本，生成清理后的序列、tails 和报告。

    参数:
        fasta: 输入 FLNC FASTA 文件（通常来自 BamTools convert）
        output_dir: 输出目录
        prefix: 输出前缀（默认在输入文件名基础上追加 _tama）
        args: 透传给 TAMA 脚本的附加参数（若有）
        tama_script: TAMA 脚本绝对路径（默认使用仓库内 gs-tama-1.0.3 路径）
    返回:
        dict: 包含压缩后的输出文件路径与版本信息文件路径
    """
    # 使用绝对路径创建并切换输出目录，避免后续相对路径重复导致的问题
    outdir = Path(os.path.abspath(os.path.expanduser(output_dir)))
    outdir.mkdir(parents=True, exist_ok=True)

    if not prefix:
        prefix = _derive_prefix_from_fasta(fasta)

    # 固定输入 fasta 的绝对路径，避免切换工作目录后相对路径失效
    fasta_abs = os.path.abspath(os.path.expanduser(fasta))

    # 解析 TAMA 脚本路径
    script_path = Path(os.path.expanduser(tama_script)) if tama_script else _default_tama_script_path()
    use_inprocess = script_path.exists()

    # 在输出目录内执行，确保生成的文件落在 outdir 下
    cwd_old = os.getcwd()
    os.chdir(str(outdir))
    try:
        if use_inprocess:
            # 使用兼容垫片在 Python3 下运行 TAMA 脚本（定义 xrange=range 并设置 sys.argv）
            argv = [str(script_path), "-f", str(fasta_abs), "-p", str(prefix)]
            if args:
                argv += shlex.split(args)
            import builtins
            if not hasattr(builtins, "xrange"):
                builtins.xrange = range  # 兼容脚本中的 xrange 用法
            sys.argv = argv
            runpy.run_path(str(script_path), run_name="__main__")
        else:
            # 回退：直接作为可执行脚本调用（需脚本在 PATH 中可用）
            cmd = [
                shutil.which("tama_flnc_polya_cleanup.py") or "tama_flnc_polya_cleanup.py",
                "-f", str(fasta_abs),
                "-p", str(prefix),
            ]
            if args:
                cmd += shlex.split(args)
            cmd_str = " ".join(cmd)
            print(f"执行命令:\n{cmd_str}\n")
            subprocess.run(cmd_str, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

        print("TAMA polyA 清理完成，开始压缩输出")
        # 压缩输出，与 nf-core 模块保持一致
        for fp in [f"{prefix}.fa", f"{prefix}_polya_flnc_report.txt", f"{prefix}_tails.fa"]:
            if Path(fp).exists():
                subprocess.run(f"gzip -f {fp}", shell=True, check=True)

        # 版本信息（与 nf-core 模块保持风格）
        # 使用仓库内的 tama_collapse.py 获取版本日期（若存在），否则标记为 unknown
        collapse_path = Path(__file__).parent / "gs-tama-1.0.3" / "tama_collapse.py"
        if collapse_path.exists():
            version_cmd = f"python3 {collapse_path} -version | grep 'tc_version_date_' | sed 's/tc_version_date_//g'"
            version = subprocess.run(version_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True).stdout.strip()
        else:
            version = "unknown"
        # 直接在当前输出目录写入版本文件
        with open("versions.yml", "w") as vf:
            vf.write(f"gstama:\n    gstama: {version}\n")

        outputs = {
            "fasta": str(outdir / f"{prefix}.fa.gz"),
            "report": str(outdir / f"{prefix}_polya_flnc_report.txt.gz"),
            "tails": str(outdir / f"{prefix}_tails.fa.gz"),
            "versions": str(outdir / "versions.yml"),
        }
        return outputs

    finally:
        os.chdir(cwd_old)


def main():
    parser = argparse.ArgumentParser(description="TAMA FLNC polyA 清理封装脚本（衔接 BamTools convert 输出）")
    parser.add_argument("--fasta", required=True, help="输入 FLNC FASTA 文件（例如 bamtools convert 的输出）")
    parser.add_argument("--outdir", required=True, help="输出目录")
    parser.add_argument("--prefix", default=None, help="输出前缀（默认在输入文件名基础上追加 _tama）")
    parser.add_argument("--args", default="", help="透传给 TAMA 脚本的附加参数")
    parser.add_argument("--tama-script", default=None, help="tama_flnc_polya_cleanup.py 的绝对路径（默认使用仓库内路径）")

    ns = parser.parse_args()

    run_tama_polyacleanup(
        fasta=ns.fasta,
        output_dir=ns.outdir,
        prefix=ns.prefix,
        args=ns.args,
        tama_script=ns.tama_script,
    )


if __name__ == "__main__":
    main()