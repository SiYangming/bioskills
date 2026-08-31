# minimap2 align Snakemake rule（从 isoseq.smk/workflow/rules/minimap2.smk 迁移）
#
# 迁移说明：
#   - 去掉 workflow/lib/helpers.py 依赖（原 rule 用 get_minimap2_reads 查 mapping 表，此处内联路径）
#   - 去掉 docker_run 分支与 MINIMAP2_DOCKER_IMAGE / SAMTOOLS_DOCKER_IMAGE 容器配置
#   - 参数通过 config["minimap2"] 可覆盖，默认与 isoseq.smk 一致
#
# 用法：include: "skills/minimap2/snakemake/local/minimap2_align.smk" 后声明目标文件即可。

MINIMAP2_BIN = config.get("minimap2", {}).get("minimap2_bin", "minimap2")
SAMTOOLS_BIN = config.get("minimap2", {}).get("samtools_bin", "samtools")
MINIMAP2_ARGS = config.get("minimap2", {}).get("args", "")
REFERENCE = config.get("minimap2", {}).get("fasta", "")

rule minimap2_align:
    """FLNC reads -> 参考基因组比对，输出排序 BAM + 索引（Iso-Seq 流程核心步骤）。"""
    input:
        # 原 isoseq.smk 用 get_minimap2_reads(wildcards, ...) 动态解析，此处内联默认路径
        reads="results/gstama/{sample}/{sample}.chunk{n}_gstama.fa.gz"
    output:
        bam="results/minimap2/{sample}/{sample}.chunk{n}.bam",
        bai="results/minimap2/{sample}/{sample}.chunk{n}.bam.bai",
        versions="results/minimap2/{sample}/{sample}.chunk{n}.versions.yml"
    params:
        minimap2_bin=MINIMAP2_BIN,
        samtools_bin=SAMTOOLS_BIN,
        args=MINIMAP2_ARGS,
        reference=REFERENCE
    threads: 8
    log:
        "logs/minimap2/{sample}_chunk{n}.log"
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        mkdir -p "$OUTDIR" "$(dirname {log})"

        REF="{params.reference}"
        READS="{input.reads}"
        OUT_BAM="{output.bam}"

        # 直接管道：minimap2 -a | samtools sort | samtools index
        {params.minimap2_bin} {params.args} -t {threads} -a "$REF" "$READS" \
            | {params.samtools_bin} sort -@ {threads} -o "$OUT_BAM" - \
            && {params.samtools_bin} index "$OUT_BAM" >> {log} 2>&1

        VER=$({params.minimap2_bin} --version)

        # Versions
        echo "minimap2:" > {output.versions}
        echo "    minimap2: $VER" >> {output.versions}
        """
