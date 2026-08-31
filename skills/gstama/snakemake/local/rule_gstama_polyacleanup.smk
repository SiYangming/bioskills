# gstama polyacleanup Snakemake rule（从 isoseq.smk/workflow/rules/gstama.smk 迁移）
#
# 迁移说明：去掉 docker_run 分支与 GSTAMA_DOCKER_IMAGE 容器配置；路径通过 config 可覆盖。

GSTAMA_BIN = config.get("gstama", {}).get("gstama_bin", "tama_flnc_polya_cleanup.py")

rule gstama_polyacleanup:
    """TAMA FLNC polyA 清理并 gzip 输出（输入：bamtools convert 的 FASTA）。"""
    input:
        fasta="results/bamtools/{sample}/{sample}.chunk{n}.fasta"
    output:
        fasta="results/gstama/{sample}/{sample}.chunk{n}_gstama.fa.gz",
        report="results/gstama/{sample}/{sample}.chunk{n}_gstama_polya_flnc_report.txt.gz",
        tails="results/gstama/{sample}/{sample}.chunk{n}_gstama_tails.fa.gz",
        versions="results/gstama/{sample}/{sample}.chunk{n}.versions.yml"
    params:
        gstama_bin=GSTAMA_BIN,
        prefix=lambda wildcards, output: output.fasta.replace(".fa.gz", "")
    threads: 1
    log:
        "logs/gstama/{sample}_chunk{n}.log"
    shell:
        """
        mkdir -p "$(dirname {output.fasta})" "$(dirname {log})"

        {params.gstama_bin} -f {input.fasta} -p "{params.prefix}" >> {log} 2>&1

        for f in "{params.prefix}.fa" "{params.prefix}_polya_flnc_report.txt" "{params.prefix}_tails.fa"; do
            [ -f "$f" ] && gzip -f "$f"
        done

        echo "gstama:" > {output.versions}
        echo "    gstama: 1.0.3" >> {output.versions}
        """
