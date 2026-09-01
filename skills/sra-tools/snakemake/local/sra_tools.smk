# sra-tools 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/nanoseq.smk/nanoseq.sh/
#   batch_prefetch.sh              prefetch -f yes -t http <srr_id>
#   batch_sra_to_fastq.sh          fastq-dump --split-3 --gzip -O <outdir> <sra>
#   batch_sra_to_fastq_parallel.sh（同 fastq-dump，GNU parallel 并行 -> 由 Snakemake 调度）
# 去掉 while 串行循环 / parallel 外部依赖 / 绝对路径（./sratoolkit.3.2.0-centos_linux64/bin/）。
# 使用前准备 envs/sra-tools.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [sra-tools=3.4.1]
# ---------------------------------------------------------------------------

# Step 1: prefetch 下载 SRA（nanoseq 默认 -f yes -t http：强制重下 + HTTP 协议）
rule sra_prefetch:
    input:
        srr_list="SRR_Acc_List.txt"
    output:
        sra="sra/{srr_id}/{srr_id}.sra"
    params:
        prefetch_bin="prefetch",
        prefetch_options="-f yes -t http"
    threads: 2
    conda:
        "envs/sra-tools.yaml"
    log:
        "logs/sra-tools/prefetch/{srr_id}.log"
    shell:
        """
        mkdir -p "$(dirname {output.sra})" "$(dirname {log})"
        "{params.prefetch_bin}" {params.prefetch_options} \
            -O "$(dirname "$(dirname {output.sra})")" \
            {wildcards.srr_id} >> {log} 2>&1
        test -s {output.sra}
        """

# Step 2: fastq-dump 转 FASTQ（nanoseq batch_sra_to_fastq*.sh 原用法：--split-3 --gzip）
rule sra_fastq_dump:
    input:
        sra="sra/{sample}/{sample}.sra"
    output:
        fastq="fastq/{sample}.fastq.gz"
    params:
        fastq_dump_bin="fastq-dump"
    threads: 4
    conda:
        "envs/sra-tools.yaml"
    log:
        "logs/sra-tools/fastq-dump/{sample}.log"
    shell:
        """
        mkdir -p "$(dirname {output.fastq})" "$(dirname {log})"
        "{params.fastq_dump_bin}" --split-3 --gzip \
            -O "$(dirname {output.fastq})" \
            {input.sra} >> {log} 2>&1
        test -s {output.fastq}
        """

# Step 3: fasterq-dump 高速转 FASTQ（官方推荐；-e 线程 / -t 临时目录）
rule sra_fasterq_dump:
    input:
        sra="sra/{sample}/{sample}.sra"
    output:
        fastq="fastq/{sample}.fastq"
    params:
        fasterq_dump_bin="fasterq-dump",
        tmpdir=config.get("tmpdir", "/tmp")
    threads: 8
    conda:
        "envs/sra-tools.yaml"
    log:
        "logs/sra-tools/fasterq-dump/{sample}.log"
    shell:
        """
        mkdir -p "$(dirname {output.fastq})" "$(dirname {log})"
        "{params.fasterq_dump_bin}" {input.sra} --split-3 \
            -O "$(dirname {output.fastq})" \
            -e {threads} -t {params.tmpdir} >> {log} 2>&1
        test -s {output.fastq}
        """
