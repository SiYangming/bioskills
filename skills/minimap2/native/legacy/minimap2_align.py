import os
import subprocess
import argparse
import shutil
from pathlib import Path


def _resolve_cpus(user_cpus):
    """根据机器可用线程数选择合理的cpus，允许用户覆盖。
    - 若用户提供正数，取不超过总线程数的值
    - 若未提供，自动选择：在可能情况下预留1个线程，避免完全占满
    """
    total = os.cpu_count() or 1
    if user_cpus is not None and user_cpus > 0:
        return min(user_cpus, total), total
    auto = max(1, total - 1)
    return auto, total


def _strip_ext(path_str: str) -> str:
    """去除常见的fasta/fastq扩展名（含gz），返回不带扩展的文件基名。"""
    base = os.path.basename(path_str)
    for suf in (".fa.gz", ".fasta.gz", ".fastq.gz", ".fa", ".fasta", ".fastq"):
        if base.endswith(suf):
            return base[: -len(suf)]
    return os.path.splitext(base)[0]


def run_minimap2_align(
    reads: str,
    reference: str = None,
    outdir: str = None,
    prefix: str = None,
    bam: bool = False,
    cigar_paf: bool = False,
    cigar_bam: bool = False,
    args: str = "",
    cpus: int = None,
    minimap2_bin: str = None,
    samtools_bin: str = None,
):
    """
    运行 minimap2 比对，兼容 nf-core minimap2/align 模块的核心行为。

    参数说明：
    - reads: 输入 FASTA/FASTQ（支持 .gz）
    - reference: 参考基因组 FASTA；若不提供，退化为 reads vs reads
    - outdir: 输出目录
    - prefix: 输出前缀（默认取 reads 文件名去扩展名）
    - bam: 输出 BAM（否则输出 PAF）
    - cigar_paf: PAF 输出包含 CIGAR（-c，仅当输出为PAF时有效）
    - cigar_bam: 在 BAM 输出中对长CIGAR写入 CG 标签（-L）
    - args: 透传 minimap2 的附加参数（例如 "-x splice -uf -k14"）
    - cpus: 线程数（默认自动选择）
    - minimap2_bin: minimap2 可执行路径（默认从 PATH 解析）
    - samtools_bin: samtools 可执行路径（用于 BAM 输出管线）
    """

    # 创建输出目录
    outdir_path = Path(outdir or ".").resolve()
    outdir_path.mkdir(parents=True, exist_ok=True)

    # 线程解析
    resolved_cpus, total_cpus = _resolve_cpus(cpus)
    print(f"检测到CPU总数: {total_cpus}, 使用线程数: {resolved_cpus}")

    # 绝对路径，避免后续工作目录变化影响
    reads_abs = os.path.abspath(os.path.expanduser(reads))
    ref_abs = os.path.abspath(os.path.expanduser(reference)) if reference else None

    # 可执行文件路径
    mm2_exec = os.path.expanduser(minimap2_bin) if minimap2_bin else (shutil.which("minimap2") or "minimap2")
    sam_exec = os.path.expanduser(samtools_bin) if samtools_bin else (shutil.which("samtools") or "samtools")

    # 输出前缀
    if not prefix:
        base_name = _strip_ext(reads_abs)
        prefix = os.path.basename(base_name)
    out_prefix = outdir_path / prefix

    # 标志位
    cigarpaf_flag = "-c" if (cigar_paf and not bam) else ""
    set_cigar_bam_flag = "-L" if (cigar_bam and bam) else ""
    ref_arg = ref_abs if ref_abs else reads_abs

    # 构建命令
    if bam:
        # 与 nf-core minimap2/align 保持一致：-a | samtools sort | samtools view -b -h -o
        cmd = (
            f"{mm2_exec} {args} -t {resolved_cpus} \"{ref_arg}\" \"{reads_abs}\" "
            f"{cigarpaf_flag} {set_cigar_bam_flag} -a | "
            f"{sam_exec} sort -@ {resolved_cpus} | "
            f"{sam_exec} view -@ {resolved_cpus} -b -h -o \"{out_prefix}.bam\""
        )
    else:
        cmd = (
            f"{mm2_exec} {args} -t {resolved_cpus} \"{ref_arg}\" \"{reads_abs}\" "
            f"{cigarpaf_flag} {set_cigar_bam_flag} -o \"{out_prefix}.paf\""
        )

    print(f"执行命令:\n{cmd}\n")

    try:
        result = subprocess.run(
            cmd,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        print("Minimap2 比对完成")

        # 版本信息写出（兼容 nf-core modules 的 versions.yml）
        version_out = subprocess.run(
            f"{mm2_exec} --version 2>&1",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        ).stdout.strip()
        with open(outdir_path / "versions.yml", "w") as vf:
            vf.write(f"minimap2_align:\n    minimap2: {version_out}\n")

        return {
            "paf": str(out_prefix) + ".paf" if not bam else None,
            "bam": str(out_prefix) + ".bam" if bam else None,
            "versions": str(outdir_path / "versions.yml"),
        }

    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise


def main():
    parser = argparse.ArgumentParser(description="Minimap2 比对封装（兼容 nf-core minimap2/align）")
    parser.add_argument("--reads", required=True, help="输入 FASTA/FASTQ（支持 .gz）")
    parser.add_argument("--reference", required=False, help="参考基因组 FASTA（可选；缺省为 reads vs reads）")
    parser.add_argument("--outdir", required=True, help="输出目录")
    parser.add_argument("--prefix", required=False, help="输出前缀（默认从 reads 文件名推断）")
    parser.add_argument("--bam", action="store_true", help="输出 BAM（否则输出 PAF）")
    parser.add_argument("--cigar-paf", action="store_true", help="在 PAF 输出中写入 CIGAR（-c）")
    parser.add_argument("--cigar-bam", action="store_true", help="在 BAM 输出中为长CIGAR写入 CG 标签（-L）")
    parser.add_argument("--args", default="", help="透传 minimap2 参数（例如 \"-x splice -uf -k14\"）")
    parser.add_argument("--cpus", type=int, default=None, help="线程数（默认自动选择）")
    parser.add_argument("--minimap2-bin", default=None, help="minimap2 可执行路径（默认从 PATH 解析）")
    parser.add_argument("--samtools-bin", default=None, help="samtools 可执行路径（用于 BAM 输出管线）")

    args = parser.parse_args()

    run_minimap2_align(
        reads=args.reads,
        reference=args.reference,
        outdir=args.outdir,
        prefix=args.prefix,
        bam=args.bam,
        cigar_paf=args.cigar_paf,
        cigar_bam=args.cigar_bam,
        args=args.args,
        cpus=args.cpus,
        minimap2_bin=args.minimap2_bin,
        samtools_bin=args.samtools_bin,
    )


if __name__ == "__main__":
    main()