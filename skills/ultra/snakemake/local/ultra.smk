# ultra / snakemake / local — ultra.smk
# ---------------------------------------------------------------------------
# 迁移自 snakemake.smk/isoseq.smk/workflow/skills/ultra/snakemake/local/ultra.smk，去掉了对
# workflow/lib/helpers.py 的全局依赖（SPECIES_INFO / get_sample_species /
# get_ultra_reads / get_index_flag / docker_run），改为 config 驱动 + 内联简化。
# 使用前请在 Snakefile 声明 config（见文件尾部注释）。
# ---------------------------------------------------------------------------

import os

# ---- 配置（与 isoseq.smk 语义一致；缺失时给默认值）----
ULTRA_BIN = config.get("ultra", {}).get("ultra_bin", "uLTRA")
ULTRA_INDEX_ARGS = config.get("ultra", {}).get("index_args", "--disable_infer")
ULTRA_ALIGN_ARGS = config.get("ultra", {}).get("align_args", "")
SAMTOOLS_BIN = config.get("samtools", {}).get("samtools_bin", "samtools")

RESOURCES_DIR = config.get("resources_dir", "resources")
OUTPUT_DIR = config.get("output_dir", "results")
ULTRA_DIR = config.get("ultra_dir", "results/ULTRA")

# 物种 -> 参考路径映射（替代原 helpers.SPECIES_INFO + get_sample_species）
SPECIES_GENOME = config.get("species_genome", {})  # {"hg38": "refs/hg38.fa"}
SPECIES_GTF = config.get("species_gtf", {})        # {"hg38": "refs/hg38.gtf"}


def _genome(wildcards):
    return SPECIES_GENOME[wildcards.species]


def _gtf(wildcards):
    return SPECIES_GTF[wildcards.species]


# ---- 参考准备 ------------------------------------------------------------ #
rule prepare_genome:
    input:
        lambda wildcards: _genome(wildcards)
    output:
        f"{RESOURCES_DIR}/{{species}}/genome.fa"
    shell:
        """
        if [[ "{input}" == *.gz ]]; then
            gzip -cd {input} > {output}
        else
            ln -sf $(readlink -f {input}) {output}
        fi
        """


rule prepare_gtf:
    input:
        lambda wildcards: _gtf(wildcards)
    output:
        f"{RESOURCES_DIR}/{{species}}/genes.gtf"
    shell:
        """
        if [[ "{input}" == *.gz ]]; then
            gzip -cd {input} | grep -v '#' > {output}
        else
            grep -v '#' {input} > {output}
        fi
        """


# ---- GTF 排序（index 前置）----------------------------------------------- #
rule sort_gtf:
    input:
        f"{RESOURCES_DIR}/{{species}}/genes.gtf"
    output:
        f"{RESOURCES_DIR}/{{species}}/genes.sorted.gtf"
    params:
        args="-k1,1 -k4,4n"
    shell:
        "sort {params.args} {input} > {output}"


# ---- uLTRA index --------------------------------------------------------- #
rule ultra_index:
    input:
        reference=f"{RESOURCES_DIR}/{{species}}/genome.fa",
        gtf=f"{RESOURCES_DIR}/{{species}}/genes.sorted.gtf"
    output:
        flag=touch(f"{OUTPUT_DIR}/INDEX/{{species}}/done")
    params:
        ultra_bin=ULTRA_BIN,
        args=ULTRA_INDEX_ARGS,
        index_dir=lambda wildcards, output: os.path.dirname(output.flag)
    threads: 8
    shell:
        """
        mkdir -p {params.index_dir}
        {params.ultra_bin} index {input.reference} {input.gtf} {params.index_dir} {params.args}
        """


# ---- uLTRA align + samtools sort ---------------------------------------- #
# 注意：原 isoseq.smk 的 reads 来自 helpers.get_ultra_reads（sample -> gstama 产物），
# 此处简化为显式通配 reads/{sample}.fa.gz；index 依赖简化为 INDEX/{species}/done，
# 调用方需保证 {sample}/{species} 通配符一致（可用 use rule 后覆盖 input）。
rule ultra_align:
    input:
        reads="reads/{sample}.fa.gz",
        index_flag=f"{OUTPUT_DIR}/INDEX/{{species}}/done"
    output:
        bam=f"{ULTRA_DIR}/{{sample}}/{{sample}}.bam"
    params:
        ultra_bin=ULTRA_BIN,
        args=ULTRA_ALIGN_ARGS,
        index_path=lambda wildcards, input: os.path.dirname(input.index_flag),
        samtools_bin=SAMTOOLS_BIN
    threads: 8
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        PREFIX="$(basename {output.bam} .bam)"
        mkdir -p "$OUTDIR"

        GENOME="{params.index_path}/genome.fa"
        if [ ! -f "$GENOME" ]; then
            GENOME="{params.index_path}/../genome.fa"
        fi

        READS="{input.reads}"
        if [[ "{input.reads}" == *.gz ]]; then
            READS_UNCOMP="$OUTDIR/reads.fa"
            gzip -cd "$READS" > "$READS_UNCOMP"
            READS="$READS_UNCOMP"
        fi

        {params.ultra_bin} align "$GENOME" "$READS" "$PWD/$OUTDIR" \
            --index {params.index_path} --prefix "$PREFIX" --t {threads} {params.args}
        {params.samtools_bin} sort -@ {threads} -o "$PWD/{output.bam}" "$PWD/$OUTDIR/$PREFIX.sam"
        rm -f "$PWD/$OUTDIR/$PREFIX.sam"
        """


# 使用前在 Snakefile 声明：
#   config.setdefault("ultra", {})
#   config["ultra"].setdefault("ultra_bin", "uLTRA")
#   config["ultra"].setdefault("index_args", "--disable_infer")
#   config["ultra"].setdefault("align_args", "")
#   config["samtools"].setdefault("samtools_bin", "samtools")
#   config.setdefault("species_genome", {"hg38": "refs/hg38.fa"})
#   config.setdefault("species_gtf", {"hg38": "refs/hg38.gtf"})
#   config.setdefault("resources_dir", "resources")
#   config.setdefault("output_dir", "results")
#   config.setdefault("ultra_dir", "results/ULTRA")
