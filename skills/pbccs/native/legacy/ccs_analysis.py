import os
import subprocess
import argparse
import json
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

def run_ccs_analysis(subreads_bam, output_dir, chunk_num, chunk_total, 
                    min_rq=0.9, min_passes=3, min_snr=2.5, 
                    min_length=10, max_length=50000, top_passes=60, cpus=None, ccs_bin=None):
    """
    调用PacBio CCS工具进行分析
    
    参数:
        subreads_bam: 输入subreads BAM文件路径
        output_dir: 输出文件目录
        chunk_num: 当前分块编号 (1-based)
        chunk_total: 总分块数
        min_rq: 最小读取质量阈值
        min_passes: 最小subread通过次数
        min_snr: 最小信噪比
        min_length: 最小序列长度
        max_length: 最大序列长度
        top_passes: 最大使用的subread通过次数
        cpus: 线程数
    """
    # 创建输出目录
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 解析样本名
    sample_name = Path(subreads_bam).stem.replace('.subreads', '')
    prefix = output_dir / f"{sample_name}.chunk{chunk_num}"
    resolved_cpus, total_cpus = _resolve_cpus(cpus)
    print(f"检测到CPU总数: {total_cpus}, 使用线程数: {resolved_cpus}")
    
    # 选择 ccs 可执行文件路径
    if ccs_bin:
        ccs_exec = os.path.expanduser(ccs_bin)
    else:
        ccs_exec = shutil.which("ccs") or "ccs"

    # 构建CCS命令
    cmd = [
        ccs_exec,
        str(subreads_bam),
        f"{prefix}.bam",
        f"--report-file {prefix}.report.txt",
        f"--report-json {prefix}.report.json",
        f"--metrics-json {prefix}.metrics.json.gz",
        f"--chunk {chunk_num}/{chunk_total}",
        f"--min-rq {min_rq}",
        f"--min-passes {min_passes}",
        f"--min-snr {min_snr}",
        f"--min-length {min_length}",
        f"--max-length {max_length}",
        f"--top-passes {top_passes}",
        f"-j {resolved_cpus}"
    ]
    
    # 拼接命令字符串
    cmd_str = ' \\\n    '.join(cmd)
    print(f"执行命令:\n{cmd_str}\n")
    
    # 执行命令
    try:
        result = subprocess.run(
            cmd_str,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        print("CCS分析完成")
        
        # 生成版本信息文件
        with open(output_dir / "versions.yml", "w") as f:
            version_output = subprocess.run(
                f"{ccs_exec} --version 2>&1 | grep 'ccs' | sed 's/^.*ccs //; s/ .*$//'",
                shell=True,
                stdout=subprocess.PIPE,
                text=True
            ).stdout.strip()
            f.write(f"PBCCS:\n    pbccs: {version_output}\n")
            
        return {
            "bam": f"{prefix}.bam",
            "pbi": f"{prefix}.bam.pbi",
            "report_txt": f"{prefix}.report.txt",
            "report_json": f"{prefix}.report.json",
            "metrics": f"{prefix}.metrics.json.gz"
        }
        
    except subprocess.CalledProcessError as e:
        print(f"命令执行失败: {e.stderr}")
        raise

def main():
    parser = argparse.ArgumentParser(description="PacBio CCS分析工具")
    parser.add_argument("--subreads", required=True, help="输入subreads BAM文件路径")
    parser.add_argument("--outdir", required=True, help="输出目录")
    parser.add_argument("--chunk-num", type=int, required=True, help="当前分块编号 (1-based)")
    parser.add_argument("--chunk-total", type=int, required=True, help="总分块数")
    parser.add_argument("--min-rq", type=float, default=0.9, help="最小读取质量阈值 (0-1)")
    parser.add_argument("--min-passes", type=int, default=3, help="最小subread通过次数")
    parser.add_argument("--min-snr", type=float, default=2.5, help="最小信噪比")
    parser.add_argument("--min-length", type=int, default=10, help="最小序列长度")
    parser.add_argument("--max-length", type=int, default=50000, help="最大序列长度")
    parser.add_argument("--top-passes", type=int, default=60, help="最大使用的subread通过次数")
    parser.add_argument("--cpus", type=int, default=None, help="线程数（默认：自动选择）")
    parser.add_argument("--ccs-bin", type=str, default=None, help="ccs可执行文件绝对路径（默认从PATH中查找）")
    
    args = parser.parse_args()
    
    # 运行CCS分析
    run_ccs_analysis(
        subreads_bam=args.subreads,
        output_dir=args.outdir,
        chunk_num=args.chunk_num,
        chunk_total=args.chunk_total,
        min_rq=args.min_rq,
        min_passes=args.min_passes,
        min_snr=args.min_snr,
        min_length=args.min_length,
        max_length=args.max_length,
        top_passes=args.top_passes,
        cpus=args.cpus,
        ccs_bin=args.ccs_bin
    )

if __name__ == "__main__":
    main()