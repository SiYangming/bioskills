# bamtools convert Snakemake rule（从 isoseq.smk/workflow/rules/bamtools.smk 迁移）
#
# 迁移说明：
#   - 去掉 workflow/lib/helpers.py 依赖（原 rule 的 input 直接引用 ISOSEQ_DIR 常量）
#   - 去掉 docker_run 分支与 BAMTOOLS_DOCKER_IMAGE 容器配置
#   - 路径通过 config["bamtools"] 可覆盖，默认与 isoseq.smk 一致
#
# 用法：include: "rules/rule_bamtools_convert.smk" 后声明目标文件即可。

BAMTOOLS_BIN = config.get("bamtools", {}).get("bamtools_bin", "bamtools")
BAMTOOLS_FORMAT = config.get("bamtools", {}).get("format", "fasta")

rule bamtools_convert:
    """BAM -> <format>（默认 fasta），Iso-Seq refine 产物转 FLNC 序列。"""
    input:
        bam="results/refine/{sample}/{sample}.chunk{n}.bam"
    output:
        out="results/bamtools/{sample}/{sample}.chunk{n}.{format}",
        versions="results/bamtools/{sample}/{sample}.chunk{n}.versions.yml"
    params:
        bamtools_bin=BAMTOOLS_BIN,
        format=BAMTOOLS_FORMAT
    threads: 1
    log:
        "logs/bamtools/{sample}_chunk{n}.log"
    shell:
        """
        OUTDIR="$(dirname {output.out})"
        mkdir -p "$OUTDIR" "$(dirname {log})"

        ARGS="-format {params.format} -in {input.bam} -out {output.out}"

        "{params.bamtools_bin}" convert $ARGS >> {log} 2>&1
        VER=$("{params.bamtools_bin}" --version | grep -e 'bamtools' | sed 's/^.*bamtools //')

        # Write versions.yml
        echo "bamtools:" > {output.versions}
        echo "    bamtools: $VER" >> {output.versions}
        """
