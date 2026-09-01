# gstama collapse Snakemake rule（从 isoseq.smk/workflow/rules/gstama.smk 迁移）
#
# 迁移说明：
#   - 去掉 workflow/lib/helpers.py 依赖（原 get_collapse_input_bam 按 aligner 查 minimap2/ultra，
#     此处内联默认 minimap2 路径；ultra 场景自行改 input）
#   - 去掉 docker_run 分支与 GSTAMA_DOCKER_IMAGE 容器配置
#   - 参考 FASTA 与 collapse 参数通过 config["gstama"] 可覆盖，默认与 isoseq.smk 一致

GSTAMA_COLLAPSE_BIN = config.get("gstama", {}).get("gstama_collapse_bin", "tama_collapse.py")
GSTAMA_REFERENCE = config.get("gstama", {}).get("fasta", "ref/ref.fa")
GSTAMA_COLLAPSE_ARGS = config.get("gstama", {}).get(
    "collapse_args", "-x no_cap -a 100 -z 100 -sj sj_priority -sjt 20 -lde 5")

rule gstama_collapse:
    """TAMA collapse 转录本去冗余（输入：minimap2 比对 BAM + 参考 FASTA）。"""
    input:
        bam="results/minimap2/{aligner}/{sample}/{sample}.chunk{n}.bam",
        reference=GSTAMA_REFERENCE
    output:
        bed="results/gstama_collapse/{aligner}/{sample}/{sample}.chunk{n}_gstama_collapsed.bed",
        report="results/gstama_collapse/{aligner}/{sample}/{sample}.chunk{n}_gstama_read.txt",
        versions="results/gstama_collapse/{aligner}/{sample}/{sample}.chunk{n}.versions.yml"
    params:
        gstama_collapse_bin=GSTAMA_COLLAPSE_BIN,
        args=GSTAMA_COLLAPSE_ARGS,
        prefix=lambda wildcards, output: output.bed.replace("_collapsed.bed", "")
    threads: 1
    log:
        "logs/gstama_collapse/{aligner}_{sample}_chunk{n}.log"
    shell:
        """
        mkdir -p "$(dirname {output.bed})" "$(dirname {log})"

        REF="{input.reference}"

        {params.gstama_collapse_bin} -s {input.bam} -f "$REF" -p "{params.prefix}" \
            -b BAM {params.args} >> {log} 2>&1

        echo "tama_collapse: 1.0.4" > {output.versions}
        """
