# isoseq3 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/isoseq.smk/workflow/rules/isoseq3.smk
# 去掉对 workflow/lib/helpers.py 的全局依赖（get_isoseq_input_bam / docker_run / ISOSEQ_DIR / LOG_DIR）：
#   - 输入改为路径模板 lima/{sample}/{sample}.chunk{n}.bam
#   - docker 分支移除，直接调用本地 isoseq3 二进制
#   - log 目录由规则内 $(dirname {log}) 创建
# 使用前准备 envs/isoseq3.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [isoseq=4.0.0]
# ---------------------------------------------------------------------------
rule isoseq3_refine:
    input:
        bam="lima/{sample}/{sample}.chunk{n}.bam",
        primers="primers.fasta"
    output:
        bam="isoseq3/{sample}/{sample}.chunk{n}.bam",
        pbi="isoseq3/{sample}/{sample}.chunk{n}.bam.pbi",
        consensus="isoseq3/{sample}/{sample}.chunk{n}.consensusreadset.xml",
        summary="isoseq3/{sample}/{sample}.chunk{n}.filter_summary.report.json",
        report="isoseq3/{sample}/{sample}.chunk{n}.report.csv"
    params:
        extra_args="--require-polya",
        isoseq_bin="isoseq3"
    threads: 8
    conda:
        "envs/isoseq3.yaml"
    log:
        "logs/isoseq3/{sample}_chunk{n}.log"
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        mkdir -p "$OUTDIR" "$(dirname {log})"

        # isoseq3 refine [options] <input> <primers> <output>
        ARGS="-j {threads} {params.extra_args} {input.bam} {input.primers} {output.bam}"

        "{params.isoseq_bin}" refine $ARGS >> {log} 2>&1
        """
