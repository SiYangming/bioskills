import os
import argparse
import subprocess
import shutil
from pathlib import Path


ALLOWED_FORMATS = {"bed", "fasta", "fastq", "json", "pileup", "sam", "yaml"}


def _derive_prefix_from_bam(bam_path: str) -> str:
    name = Path(bam_path).name
    if name.endswith(".bam"):
        return name[:-4]
    return Path(bam_path).stem


def run_bamtools_convert(
    bam: str,
    output_dir: str,
    fmt: str = "fasta",
    prefix: str = None,
    args: str = "",
    bamtools_bin: str = None,
):
    """
    使用 BamTools 将 BAM 转换为指定格式（默认 FASTA）。

    参数:
        bam: 输入 BAM 文件路径（例如 IsoSeq3 refine 的输出）
        output_dir: 输出目录
        fmt: 目标格式，支持 bed/fasta/fastq/json/pileup/sam/yaml（默认 fasta）
        prefix: 输出前缀（默认从 bam 文件名推断）
        args: 透传给 bamtools convert 的附加参数，例如 "-region chr1:100-200"
        bamtools_bin: bamtools 可执行文件绝对路径（默认从 PATH 中查找）
    返回:
        dict: 包含输出文件路径与版本文件路径
    """

    if fmt not in ALLOWED_FORMATS:
        raise ValueError(f"不支持的格式: {fmt}，允许值: {sorted(ALLOWED_FORMATS)}")

    outdir = Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    if not prefix:
        prefix = _derive_prefix_from_bam(bam)
    out_path = outdir / f"{prefix}.{fmt}"

    # 选择 bamtools 可执行文件路径
    if bamtools_bin:
        bamtools_exec = os.path.expanduser(bamtools_bin)
    else:
        bamtools_exec = shutil.which("bamtools") or "bamtools"

    # 构建命令
    cmd_parts = [
        bamtools_exec,
        "convert",
    ]
    if args:
        cmd_parts.append(args)
    cmd_parts += [
        f"-format {fmt}",
        f"-in {bam}",
        f"-out {out_path}",
    ]

    cmd_str = ' \\\n    '.join(cmd_parts)
    print(f"执行命令:\n{cmd_str}\n")

    try:
        result = subprocess.run(
            cmd_str,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        print("BamTools convert 完成")

        # 版本信息（与 nf-core 模块一致，使用同一路径；静默 stderr）
        version_cmd = f"{bamtools_exec} --version | grep -e 'bamtools' | sed 's/^.*bamtools //'"
        version = subprocess.run(
            version_cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        ).stdout.strip()
        with open(outdir / "versions.yml", "w") as vf:
            vf.write(f"bamtools:\n    bamtools: {version}\n")

        return {
            "out": str(out_path),
            "versions": str(outdir / "versions.yml"),
        }

    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise


def main():
    parser = argparse.ArgumentParser(description="BamTools convert 封装脚本（对接 IsoSeq3 refine 输出）")
    parser.add_argument("--bam", required=True, help="输入 BAM 文件路径（通常为 refine 的产物）")
    parser.add_argument("--outdir", required=True, help="输出目录")
    parser.add_argument("--format", default="fasta", choices=sorted(ALLOWED_FORMATS), help="输出格式（默认 fasta）")
    parser.add_argument("--prefix", default=None, help="输出前缀（默认从 bam 文件名推断）")
    parser.add_argument("--args", default="", help="透传给 bamtools convert 的附加参数，例如 '-region chr1:100-200'")
    parser.add_argument("--bamtools-bin", default=None, help="bamtools 可执行文件绝对路径（默认从 PATH 中查找）")

    ns = parser.parse_args()

    run_bamtools_convert(
        bam=ns.bam,
        output_dir=ns.outdir,
        fmt=ns.format,
        prefix=ns.prefix,
        args=ns.args,
        bamtools_bin=ns.bamtools_bin,
    )


if __name__ == "__main__":
    main()