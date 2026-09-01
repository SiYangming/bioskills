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


def _derive_prefix_from_bam(bam_path: str) -> str:
    name = Path(bam_path).name
    if name.endswith('.bam'):
        return name[:-4]
    return Path(bam_path).stem


def run_isoseq3_refine(
    bam: str,
    primers: str,
    output_dir: str,
    prefix: str = None,
    args: str = '',
    cpus: int = None,
    isoseq3_bin: str = None,
):
    """
    调用 IsoSeq3 refine 去除 polyA 尾和人工连接体。

    参数:
        bam: lima 生成的清理过的 ccs BAM 文件
        primers: 引物 fasta 文件
        output_dir: 输出目录
        prefix: 输出文件前缀（默认从 bam 文件名推断）
        args: 透传给 isoseq3 refine 的附加参数字符串
        cpus: 线程数（默认：自动选择）
        isoseq3_bin: isoseq3 可执行文件绝对路径（默认从 PATH 中查找）
    """
    outdir = Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    resolved_cpus, total_cpus = _resolve_cpus(cpus)
    print(f"检测到CPU总数: {total_cpus}, 使用线程数: {resolved_cpus}")

    if not prefix:
        prefix = _derive_prefix_from_bam(bam)
    out_bam = outdir / f"{prefix}.bam"

    # 选择 isoseq3 可执行文件路径
    if isoseq3_bin:
        isoseq3_exec = os.path.expanduser(isoseq3_bin)
    else:
        isoseq3_exec = shutil.which('isoseq3') or 'isoseq3'

    # 构建命令
    cmd_parts = [
        isoseq3_exec,
        'refine',
        f"-j {resolved_cpus}",
    ]
    if args:
        cmd_parts.append(args)
    cmd_parts += [
        str(bam),
        str(primers),
        str(out_bam),
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
        print("IsoSeq3 refine 完成")

        # 版本信息（使用相同的 isoseq3 可执行路径；静默 stderr 以防 PATH 不含 isoseq3 时噪声）
        version_cmd = f"{isoseq3_exec} refine --version | head -n 1 | sed 's/isoseq refine //g' | sed 's/ (commit.*//g'"
        version = subprocess.run(
            version_cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        ).stdout.strip()
        with open(outdir / 'versions.yml', 'w') as vf:
            vf.write(f"isoseq3:\n    isoseq3: {version}\n")

        outputs = {
            'bam': str(out_bam),
            'pbi': str(out_bam) + '.pbi',
            'consensusreadset': str(outdir / f"{prefix}.consensusreadset.xml"),
            'summary': str(outdir / f"{prefix}.filter_summary.report.json"),
            'report': str(outdir / f"{prefix}.report.csv"),
            'versions': str(outdir / 'versions.yml'),
        }
        return outputs

    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise


def main():
    parser = argparse.ArgumentParser(description="IsoSeq3 refine 分析工具")
    parser.add_argument('--bam', required=True, help='输入 BAM 文件（lima 产物）')
    parser.add_argument('--primers', required=True, help='引物 fasta 文件路径')
    parser.add_argument('--outdir', required=True, help='输出目录')
    parser.add_argument('--prefix', default=None, help='输出前缀（默认从 bam 文件名推断）')
    parser.add_argument('--args', default='', help='透传给 isoseq3 refine 的附加参数，例如"--require-polya --min-polya-length 20"')
    parser.add_argument('--cpus', type=int, default=None, help='线程数（默认：自动选择）')
    parser.add_argument('--isoseq3-bin', type=str, default=None, help='isoseq3 可执行文件绝对路径（默认从 PATH 中查找）')

    args_ns = parser.parse_args()

    run_isoseq3_refine(
        bam=args_ns.bam,
        primers=args_ns.primers,
        output_dir=args_ns.outdir,
        prefix=args_ns.prefix,
        args=args_ns.args,
        cpus=args_ns.cpus,
        isoseq3_bin=args_ns.isoseq3_bin,
    )


if __name__ == '__main__':
    main()