# lima 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/isoseq.smk/workflow/skills/lima/snakemake/local/lima.smk
# 去掉对 workflow/lib/helpers.py 的全局依赖（get_lima_input / docker_run / LIMA_DIR / LOG_DIR）：
#   - 输入改为路径模板 ccs/{sample}/{sample}.chunk{n}.bam
#   - docker 分支移除，直接调用本地 lima 二进制
#   - log 目录由规则内 $(dirname {log}) 创建
# 使用前准备 envs/lima.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [lima=2.9.0]
# ---------------------------------------------------------------------------
rule lima:
    input:
        bam="ccs/{sample}/{sample}.chunk{n}.bam",
        primers="primers.fasta"
    output:
        bam="lima/{sample}/{sample}.chunk{n}.bam",
        pbi="lima/{sample}/{sample}.chunk{n}.bam.pbi",
        report="lima/{sample}/{sample}.chunk{n}.lima.report",
        summary="lima/{sample}/{sample}.chunk{n}.lima.summary",
        counts="lima/{sample}/{sample}.chunk{n}.lima.counts"
    params:
        # Iso-Seq 场景建议配置为 "--isoseq --peek-guess"
        extra_args="",
        lima_bin="lima"
    threads: 8
    conda:
        "envs/lima.yaml"
    log:
        "logs/lima/{sample}_chunk{n}.log"
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        mkdir -p "$OUTDIR" "$(dirname {log})"

        # lima <reads> <primers> <out> [extra] -j N
        ARGS="{input.bam} {input.primers} {output.bam} {params.extra_args} -j {threads}"

        "{params.lima_bin}" $ARGS >> {log} 2>&1
        """
