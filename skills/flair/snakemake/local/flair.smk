# flair 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh
# 去掉 nohup/PID/LOCK 后台运行封装与 $HOME/miniconda3 绝对路径依赖：
#   - 三段链路拆为三个 rule：flair_bam2bed12 / flair_annotate / flair_collapse
#   - 路径模板化：alignment/{sample}.sorted.bam -> bed12/ -> annotated/ -> consensus/
#   - flair collapse 保留 direct RNA-seq 优化参数（--trust_ends 等，值内联）
# 使用前准备 envs/flair.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [flair=3.0.0b1, minimap2]
# ---------------------------------------------------------------------------

# Step 1: BAM -> BED12（bam2Bed12 写 stdout）
rule flair_bam2bed12:
    input:
        bam="alignment/{sample}.sorted.bam"
    output:
        bed12="bed12/{sample}.bed12"
    params:
        bam2bed12_bin="bam2Bed12"
    threads: 4
    conda:
        "envs/flair.yaml"
    log:
        "logs/flair/{sample}_bam2bed12.log"
    shell:
        """
        mkdir -p "$(dirname {output.bed12})" "$(dirname {log})"
        "{params.bam2bed12_bin}" -i {input.bam} > {output.bed12} 2>> {log}
        test -s {output.bed12}
        """

# Step 2: BED12 + GTF -> 带基因注释 BED（identify_gene_isoform）
rule flair_annotate:
    input:
        bed12="bed12/{sample}.bed12",
        gtf=config.get("gtf_annotation", "ref/gencode.v49.annotation.gtf")
    output:
        annotated_bed="annotated/{sample}.annotated.bed"
    params:
        identify_bin="identify_gene_isoform"
    threads: 4
    conda:
        "envs/flair.yaml"
    log:
        "logs/flair/{sample}_flair_annotate.log"
    shell:
        """
        mkdir -p "$(dirname {output.annotated_bed})" "$(dirname {log})"
        "{params.identify_bin}" {input.bed12} {input.gtf} {output.annotated_bed} 2>> {log}
        test -s {output.annotated_bed}
        """

# Step 3: flair collapse 聚类去冗余（direct RNA-seq 优化参数，值内联自 nanoseq config）
rule flair_collapse:
    input:
        annotated_bed="annotated/{sample}.annotated.bed",
        genome=config.get("genome_fasta", "ref/hg38.fa"),
        reads="fastq/{sample}.fastq.gz",
        gtf=config.get("gtf_annotation", "ref/gencode.v49.annotation.gtf")
    output:
        fasta="consensus/{sample}.flair.collapse.fasta",
        counts="consensus/{sample}.isoform.counts.txt"
    params:
        flair_bin="flair",
        min_support=3,
        end_window=100,
        intpriming_threshold=30,
        mm2_args="-I8g,--MD"
    threads: 8
    conda:
        "envs/flair.yaml"
    log:
        "logs/flair/{sample}_flair_collapse.log"
    shell:
        """
        mkdir -p "$(dirname {output.fasta})" "$(dirname {log})"

        "{params.flair_bin}" collapse \
            -q {input.annotated_bed} \
            -g {input.genome} \
            -r {input.reads} \
            -o "$(dirname {output.fasta})/{wildcards.sample}" \
            -t {threads} \
            -f {input.gtf} \
            -s {params.min_support} \
            -w {params.end_window} \
            --trust_ends \
            --remove_internal_priming \
            --intprimingthreshold {params.intpriming_threshold} \
            --stringent \
            --check_splice \
            --mm2_args={params.mm2_args} \
            --quiet >> {log} 2>&1

        test -s {output.fasta}
        """
