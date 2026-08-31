import os
import argparse
import subprocess
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


def _infer_out_ext(reads_path: str) -> str:
    name = Path(reads_path).name
    if name.endswith('.bam'):
        return 'bam'
    if name.endswith('.fasta.gz'):
        return 'fasta.gz'
    if name.endswith('.fastq.gz'):
        return 'fastq.gz'
    if name.endswith('.fasta'):
        return 'fasta'
    if name.endswith('.fastq'):
        return 'fastq'
    return 'bam'


def _derive_prefix_from_reads(reads_path: str) -> str:
    name = Path(reads_path).name
    for suf in ('.bam', '.fasta.gz', '.fastq.gz', '.fasta', '.fastq'):
        if name.endswith(suf):
            return name[: -len(suf)]
    return Path(reads_path).stem


def run_lima_analysis(
    reads: str,
    primers: str,
    output_dir: str,
    prefix: str = None,
    args: str = '',
    cpus: int = None,
    lima_bin: str = None,
):
    """
    调用 PacBio lima 进行条形码拆分与引物去除。

    参数:
        reads: 输入 reads 文件 (bam/fasta/fasta.gz/fastq/fastq.gz)
        primers: 引物 fasta 文件
        output_dir: 输出目录
        prefix: 输出文件前缀（默认从 reads 推断）
        args: 透传给 lima 的附加参数字符串
        cpus: 线程数（默认：自动选择）
        lima_bin: lima 可执行文件绝对路径（默认从 PATH 中查找）
    """
    outdir = Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    resolved_cpus, total_cpus = _resolve_cpus(cpus)
    print(f"检测到CPU总数: {total_cpus}, 使用线程数: {resolved_cpus}")

    out_ext = _infer_out_ext(reads)
    if not prefix:
        prefix = _derive_prefix_from_reads(reads)
    out_path = outdir / f"{prefix}.{out_ext}"

    # 选择 lima 可执行文件路径
    if lima_bin:
        lima_exec = os.path.expanduser(lima_bin)
    else:
        lima_exec = shutil.which('lima') or 'lima'

    # 构建命令
    cmd_parts = [
        lima_exec,
        str(reads),
        str(primers),
        str(out_path),
        f"-j {resolved_cpus}",
    ]
    if args:
        cmd_parts.append(args)

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
        print("Lima分析完成")

        # 版本信息
        version_cmd = f"{lima_exec} --version | head -n1 | sed 's/lima //g' | sed 's/ (.\+//g'"
        version = subprocess.run(
            version_cmd,
            shell=True,
            stdout=subprocess.PIPE,
            universal_newlines=True,
        ).stdout.strip()
        with open(outdir / 'versions.yml', 'w') as vf:
            vf.write(f"lima:\n    lima: {version}\n")

        outputs = {
            'demux': str(out_path),
            'pbi': str(out_path) + '.pbi' if out_ext == 'bam' else None,
            'counts': str(outdir / f"{prefix}.counts"),
            'report': str(outdir / f"{prefix}.report"),
            'summary': str(outdir / f"{prefix}.summary"),
            'clips': str(outdir / f"{prefix}.clips"),
            'guess': str(outdir / f"{prefix}.guess"),
            'json': str(outdir / f"{prefix}.json"),
            'xml': str(outdir / f"{prefix}.xml"),
            'versions': str(outdir / 'versions.yml'),
        }
        return outputs

    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise


def main():
    parser = argparse.ArgumentParser(description="PacBio Lima分析工具")
    parser.add_argument('--reads', required=True, help='输入reads文件路径 (bam/fasta/fasta.gz/fastq/fastq.gz)')
    parser.add_argument('--primers', required=True, help='引物fasta文件路径')
    parser.add_argument('--outdir', required=True, help='输出目录')
    parser.add_argument('--prefix', default=None, help='输出前缀（默认从reads文件名推断）')
    parser.add_argument('--args', default='', help='透传给lima的附加参数字符串，例如"--isoseq --peek-guess"')
    parser.add_argument('--cpus', type=int, default=None, help='线程数（默认：自动选择）')
    parser.add_argument('--lima-bin', type=str, default=None, help='lima可执行文件绝对路径（默认从PATH中查找）')

    args_ns = parser.parse_args()

    run_lima_analysis(
        reads=args_ns.reads,
        primers=args_ns.primers,
        output_dir=args_ns.outdir,
        prefix=args_ns.prefix,
        args=args_ns.args,
        cpus=args_ns.cpus,
        lima_bin=args_ns.lima_bin,
    )


if __name__ == '__main__':
    main()
