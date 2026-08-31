import os
import shutil
import subprocess
import argparse
from pathlib import Path


def _resolve_cpus(user_cpus):
    total = os.cpu_count() or 1
    if user_cpus is not None and user_cpus > 0:
        return min(user_cpus, total), total
    auto = max(1, total - 1)
    return auto, total


def _strip_ext(path_str: str) -> str:
    base = os.path.basename(path_str)
    for suf in (".fa.gz", ".fasta.gz", ".fastq.gz", ".fa", ".fasta", ".fastq"):
        if base.endswith(suf):
            return base[: -len(suf)]
    return os.path.splitext(base)[0]


def cmd_run(cmd: str, env: dict | None = None):
    print(f"执行命令:\n{cmd}\n")
    try:
        return subprocess.run(
            cmd,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
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


def subcmd_gunzip(archive: str, outdir: str, args: str = ""):
    outdir_path = Path(outdir).resolve()
    outdir_path.mkdir(parents=True, exist_ok=True)
    archive_abs = os.path.abspath(os.path.expanduser(archive))
    out_name = os.path.basename(archive_abs)
    if not out_name.endswith(".gz"):
        raise ValueError("gunzip 子模块要求输入以 .gz 结尾的文件")
    out_name = out_name[:-3]
    out_file = outdir_path / out_name

    cmd = f"gzip -cd {args} \"{archive_abs}\" > \"{out_file}\""
    cmd_run(cmd)

    # 写 versions.yml（兼容 nf-core/gunzip）
    ver = subprocess.run(
        "gunzip --version 2>&1",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout.strip()
    with open(outdir_path / "versions.yml", "w") as vf:
        vf.write(f"gunzip:\n    gunzip: {ver}\n")

    print(f"解压完成: {out_file}")
    return str(out_file)


def subcmd_index(fasta: str, gtf: str, outdir: str, args: str = "", ultra_bin: str = None):
    outdir_path = Path(outdir).resolve()
    outdir_path.mkdir(parents=True, exist_ok=True)
    fasta_abs = os.path.abspath(os.path.expanduser(fasta))
    gtf_abs = os.path.abspath(os.path.expanduser(gtf))
    ultra_exec = os.path.expanduser(ultra_bin) if ultra_bin else (shutil.which("uLTRA") or "uLTRA")

    # 验证 GTF 文件存在且非空
    if not os.path.isfile(gtf_abs):
        raise FileNotFoundError(f"未找到 GTF 文件: {gtf_abs}")
    if os.path.getsize(gtf_abs) == 0:
        raise RuntimeError(f"GTF 文件为空: {gtf_abs}（请检查上游排序/输入路径是否正确）")

    # 若参考 FASTA 为压缩格式，先解压到 outdir（避免 uLTRA index 读取失败）
    fasta_for_index = fasta_abs
    if fasta_abs.endswith(".fa.gz") or fasta_abs.endswith(".fasta.gz"):
        base = os.path.basename(fasta_abs)
        if base.endswith('.fa.gz'):
            dec_name = base[:-len('.fa.gz')] + '.fa'
        else:
            dec_name = base[:-len('.fasta.gz')] + '.fasta'
        dec_path = outdir_path / dec_name
        if not dec_path.exists():
            cmd_run(f"gzip -cd \"{fasta_abs}\" > \"{dec_path}\"")
        fasta_for_index = str(dec_path)

    # 在 outdir 中运行，与 nf-core 行为保持一致
    cmd = f"cd \"{outdir_path}\" && {ultra_exec} index \"{fasta_for_index}\" \"{gtf_abs}\" ./ {args}"
    cmd_run(cmd)

    # 收集输出
    pickle_files = list(outdir_path.glob("*.pickle"))
    db_files = list(outdir_path.glob("*.db"))
    if not pickle_files or not db_files:
        raise RuntimeError("未找到 uLTRA index 生成的 *.pickle 或 *.db 文件")

    ver = subprocess.run(
        f"{ultra_exec} --version 2>&1",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout.strip()
    with open(outdir_path / "versions.yml", "w") as vf:
        vf.write(f"ultra_index:\n    ultra: {ver}\n")

    print(f"索引完成: pickle={pickle_files[0]} db={db_files[0]}")
    return str(pickle_files[0]), str(db_files[0])


def subcmd_align(
    reads: str,
    genome: str,
    index_dir: str,
    outdir: str,
    prefix: str = None,
    cpus: int = None,
    args: str = "",
    args2: str = "",
    ultra_bin: str = None,
    samtools_bin: str = None,
    minimap2_bin: str = None,
    namfinder_bin: str = None,
):
    outdir_path = Path(outdir).resolve()
    outdir_path.mkdir(parents=True, exist_ok=True)
    reads_abs = os.path.abspath(os.path.expanduser(reads))
    genome_abs = os.path.abspath(os.path.expanduser(genome))
    index_dir_path = Path(os.path.abspath(os.path.expanduser(index_dir)))
    ultra_exec = os.path.expanduser(ultra_bin) if ultra_bin else (shutil.which("uLTRA") or "uLTRA")
    sam_exec = os.path.expanduser(samtools_bin) if samtools_bin else (shutil.which("samtools") or "samtools")

    # 线程
    resolved_cpus, total_cpus = _resolve_cpus(cpus)
    print(f"检测到CPU总数: {total_cpus}, 使用线程数: {resolved_cpus}")

    # 前缀
    if not prefix:
        prefix = os.path.basename(_strip_ext(reads_abs))
    out_prefix = outdir_path / prefix

    # 将索引文件复制到 outdir（与 nf-core 模块在工作目录读取索引一致）
    pickle_files = list(index_dir_path.glob("*.pickle"))
    db_files = list(index_dir_path.glob("*.db"))
    if not pickle_files or not db_files:
        raise RuntimeError("index_dir 中未找到 *.pickle 或 *.db 文件")
    for f in pickle_files + db_files:
        dest = outdir_path / f.name
        if not dest.exists():
            shutil.copy2(str(f), str(dest))

    # 若参考 FASTA 为压缩格式，先解压到 outdir（避免 uLTRA align 读取失败）
    genome_for_align = genome_abs
    if genome_abs.endswith(".fa.gz") or genome_abs.endswith(".fasta.gz"):
        base = os.path.basename(genome_abs)
        if base.endswith('.fa.gz'):
            dec_name = base[:-len('.fa.gz')] + '.fa'
        else:
            dec_name = base[:-len('.fasta.gz')] + '.fasta'
        dec_path = outdir_path / dec_name
        if not dec_path.exists():
            cmd_run(f"gzip -cd \"{genome_abs}\" > \"{dec_path}\"")
        genome_for_align = str(dec_path)

    # 预检查 minimap2 可用性（uLTRA 在预过滤中调用 minimap2）
    mm_exec = None
    if minimap2_bin:
        mm_path = os.path.expanduser(minimap2_bin)
        if os.path.isfile(mm_path) and os.access(mm_path, os.X_OK):
            mm_exec = mm_path
        else:
            # 允许传递可执行名称（例如已在 PATH 中）
            mm_exec = shutil.which(mm_path)
        if not mm_exec:
            raise FileNotFoundError(f"未找到 minimap2 可执行文件: {minimap2_bin}。请确认路径或使用 conda/mamba 安装 minimap2。")
    else:
        mm_exec = shutil.which("minimap2")
        if not mm_exec:
            raise FileNotFoundError(
                "未检测到 minimap2（uLTRA 需要）。请安装并确保在 PATH 中，例如:\n"
                "  conda install -c bioconda minimap2\n"
                "或 mamba install -c bioconda minimap2；也可通过 --minimap2-bin 显式指定路径。"
            )

    # 预检查 namfinder 可用性（uLTRA 在 NAM 查找中调用 namfinder）
    nf_exec = None
    if namfinder_bin:
        nf_path = os.path.expanduser(namfinder_bin)
        if os.path.isfile(nf_path) and os.access(nf_path, os.X_OK):
            nf_exec = nf_path
        else:
            nf_exec = shutil.which(nf_path)
        if not nf_exec:
            raise FileNotFoundError(f"未找到 namfinder 可执行文件: {namfinder_bin}。请确认路径或通过 conda/mamba 安装 ultra_bioinformatics，其中包含 namfinder。")
    else:
        nf_exec = shutil.which("namfinder")
        if not nf_exec:
            raise FileNotFoundError(
                "未检测到 namfinder（uLTRA 需要）。请安装 ultra_bioinformatics 并确保在 PATH 中，例如:\n"
                "  conda install -c bioconda ultra_bioinformatics\n"
                "或 mamba install -c bioconda ultra_bioinformatics；也可通过 --namfinder-bin 显式指定路径。"
            )

    # 为子进程注入 PATH，确保 uLTRA 能找到 minimap2 / namfinder
    run_env = os.environ.copy()
    mm_dir = os.path.dirname(mm_exec)
    if mm_dir:
        run_env["PATH"] = f"{mm_dir}:{run_env.get('PATH', '')}"
    nf_dir = os.path.dirname(nf_exec)
    if nf_dir:
        run_env["PATH"] = f"{nf_dir}:{run_env.get('PATH', '')}"

    # uLTRA 对齐并由 samtools sort 生成 BAM
    cmd = (
        f"cd \"{outdir_path}\" && "
        f"{ultra_exec} align \"{genome_for_align}\" \"{reads_abs}\" ./  --t {resolved_cpus} --prefix {prefix} --index ./ {args} && "
        f"{sam_exec} sort --threads {resolved_cpus} -o \"{out_prefix}.bam\" -O BAM {args2} \"{out_prefix}.sam\" && "
        f"rm \"{out_prefix}.sam\""
    )
    cmd_run(cmd, env=run_env)

    # 版本信息
    ultra_ver = subprocess.run(
        f"{ultra_exec} --version 2>&1",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout.strip()
    sam_ver = subprocess.run(
        f"{sam_exec} --version 2>&1",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout.strip()
    with open(outdir_path / "versions.yml", "w") as vf:
        vf.write(f"ultra_align:\n    ultra: {ultra_ver}\n    samtools: {sam_ver}\n")

    print(f"对齐完成: {out_prefix}.bam")
    return str(out_prefix) + ".bam"


def subcmd_sort(gtf: str, outdir: str, prefix: str = None, args: str = ""):
    outdir_path = Path(outdir).resolve()
    outdir_path.mkdir(parents=True, exist_ok=True)
    gtf_abs = os.path.abspath(os.path.expanduser(gtf))

    # 输入存在性检查
    if not os.path.isfile(gtf_abs):
        raise FileNotFoundError(f"未找到 GTF 文件: {gtf_abs}")

    # 仅用于在 index 前对 GTF 排序；默认输出为 <prefix>.sorted.gtf
    if not prefix:
        base = os.path.basename(gtf_abs)
        if base.endswith('.gtf.gz'):
            prefix = base[:-len('.gtf.gz')]
        elif base.endswith('.gtf'):
            prefix = base[:-len('.gtf')]
        else:
            prefix = Path(gtf_abs).stem
    output_file = outdir_path / f"{prefix}.sorted.gtf"

    # 使用典型 GTF 排序键：按染色体列（第1列）+ 起始位点（第4列，数值）
    # 支持 .gtf 与 .gtf.gz：若为压缩文件则先解压再排序
    if gtf_abs.endswith('.gz'):
        # 使用 bash -o pipefail 确保上游 gzip 失败时整体报错，而不是生成空文件
        cmd = (
            f"bash -o pipefail -c 'LC_ALL=C gzip -cd \"{gtf_abs}\" | sort {args} -k1,1 -k4,4n > \"{output_file}\"'"
        )
    else:
        cmd = f"LC_ALL=C sort {args} -k1,1 -k4,4n \"{gtf_abs}\" > \"{output_file}\""
    cmd_run(cmd)

    # 输出非空校验
    if not os.path.isfile(output_file) or os.path.getsize(output_file) == 0:
        raise RuntimeError(
            f"排序后得到空的 GTF 文件: {output_file}。可能原因：输入路径错误或 gzip 解压失败。请检查 GTF 路径与权限。"
        )

    # 版本信息（与 nf-core 模块一致，工具不提供稳定 CLI 版本）
    with open(outdir_path / "versions.yml", "w") as vf:
        vf.write("GNU_SORT:\n    coreutils: 9.1\n")

    print(f"GTF 排序完成: {output_file}")
    return str(output_file)


def main():
    parser = argparse.ArgumentParser(description="ULTRA 对接封装：gunzip / index / align / sort")
    subparsers = parser.add_subparsers(dest="subcmd", required=True)

    # gunzip
    p_gz = subparsers.add_parser("gunzip", help="解压 .gz 序列文件为原始格式")
    p_gz.add_argument("--archive", required=True, help="输入 .gz 文件")
    p_gz.add_argument("--outdir", required=True, help="输出目录")
    p_gz.add_argument("--args", default="", nargs='?', help="透传 gzip 参数，例如 -S 或 -d 相关选项（可选）")

    # index
    p_idx = subparsers.add_parser("index", help="运行 uLTRA index 生成 *.pickle 与 *.db")
    p_idx.add_argument("--fasta", required=True, help="参考基因组 FASTA")
    p_idx.add_argument("--gtf", required=True, help="参考注释 GTF")
    p_idx.add_argument("--outdir", required=True, help="索引输出目录")
    p_idx.add_argument("--args", default="", nargs='?', help="透传 uLTRA index 参数（可选）")
    p_idx.add_argument("--ultra-bin", default=None, help="uLTRA 可执行路径")

    # align
    p_aln = subparsers.add_parser("align", help="运行 uLTRA align 生成 BAM")
    p_aln.add_argument("--reads", required=True, help="输入 reads（fasta/fastq，不支持 .gz）")
    p_aln.add_argument("--genome", required=True, help="参考基因组 FASTA")
    p_aln.add_argument("--index-dir", required=True, help="包含 *.pickle 与 *.db 的索引目录")
    p_aln.add_argument("--outdir", required=True, help="输出目录")
    p_aln.add_argument("--prefix", default=None, help="输出前缀（默认从 reads 推断）")
    p_aln.add_argument("--cpus", type=int, default=None, help="线程数（默认自动选择）")
    p_aln.add_argument("--args", default="", nargs='?', help="透传 uLTRA align 附加参数（可选）")
    p_aln.add_argument("--args2", default="", nargs='?', help="透传 samtools sort 附加参数（可选）")
    p_aln.add_argument("--ultra-bin", default=None, help="uLTRA 可执行路径")
    p_aln.add_argument("--samtools-bin", default=None, help="samtools 可执行路径")
    p_aln.add_argument("--minimap2-bin", default=None, help="minimap2 可执行路径（uLTRA 预过滤使用）")
    p_aln.add_argument("--namfinder-bin", default=None, help="namfinder 可执行路径（uLTRA NAM 查找使用）")

    # sort（用于在 index 前对 GTF 排序）
    p_sort = subparsers.add_parser("sort", help="在 index 之前对 GTF 排序")
    p_sort.add_argument("--gtf", required=True, help="输入 GTF 文件")
    p_sort.add_argument("--outdir", required=True, help="输出目录")
    p_sort.add_argument("--prefix", default=None, help="输出前缀（默认取输入文件名 stem）")
    p_sort.add_argument("--args", default="", nargs='?', help="透传 sort 附加参数，例如 --parallel 或 -S（可选）")

    args = parser.parse_args()

    if args.subcmd == "gunzip":
        subcmd_gunzip(args.archive, args.outdir, args.args)
    elif args.subcmd == "index":
        subcmd_index(args.fasta, args.gtf, args.outdir, args.args, args.ultra_bin)
    elif args.subcmd == "align":
        subcmd_align(
            args.reads,
            args.genome,
            args.index_dir,
            args.outdir,
            args.prefix,
            args.cpus,
            args.args,
            args.args2,
            args.ultra_bin,
            args.samtools_bin,
            args.minimap2_bin,
            args.namfinder_bin,
        )
    elif args.subcmd == "sort":
        subcmd_sort(args.gtf, args.outdir, args.prefix, args.args)


if __name__ == "__main__":
    main()