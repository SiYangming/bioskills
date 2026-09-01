# dorado 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/nanoseq.smk/workflow/Snakefile 的 DORADO_FAST5_TO_FASTQ 规则
#   + config/config.yaml 的 dorado 段（enable_dorado 开关 / model / docker_image）。
# 原规则：
#   rule DORADO_FAST5_TO_FASTQ:
#       params: model = config.get("dorado", {}).get("model", "rna004_130bps_sup@v5.1.0"),
#               docker_image = config.get("dorado", {}).get("docker_image", "docker.1ms.run/nanoporetech/dorado:latest")
#       shell: dorado basecaller {params.model} {input.pod5} --estimate-poly-a > {output.fastq}
# 迁移点：
#   - enable_dorado 为 false 时整条链路被跳过（rule all 不收集输出）
#   - dorado 不在 bioconda，rule 用 container（默认 docker.1ms.run/nanoporetech/dorado:latest）
#   - --estimate-poly-a 保留（nanoseq 原规则），输出 FASTQ
# ---------------------------------------------------------------------------

# Step 1: raw 信号（POD5/FAST5）-> FASTQ（nanoseq DORADO_FAST5_TO_FASTQ 等价规则）
# 注意：dorado basecaller 内部做 basecalling 不需要 Snakemake 的 --cores；
#       threads 用于 --num-workers（若 dorado 版本支持）。
rule dorado_basecall:
    input:
        pod5=lambda wc: f"{SAMPLES[wc.sample]['input_file']}/{wc.sample}.pod5"
    output:
        fastq="01_DORADO_BASECALL/{sample}.fastq"
    params:
        model=config.get("dorado", {}).get("model", "rna004_130bps_sup@v5.1.0"),
        docker_image=config.get("dorado", {}).get("docker_image", "docker.1ms.run/nanoporetech/dorado:latest"),
        exec_mode=config.get("dorado", {}).get("exec_mode", config.get("exec_mode", "native"))
    threads: 8
    container:
        lambda wc, output, params: params.docker_image if params.exec_mode == "docker" else None
    log:
        "logs/dorado/{sample}_basecall.log"
    shell:
        """
        mkdir -p "$(dirname {output.fastq})" "$(dirname {log})"
        dorado basecaller {params.model} {input.pod5} --estimate-poly-a > {output.fastq} 2>> {log}
        test -s {output.fastq}
        """

# Step 2: barcode 拆分（可选；nanoseq 流程未内置，按 dorado 官方用法补充）
rule dorado_demux:
    input:
        reads="01_DORADO_BASECALL/{sample}.fastq"
    output:
        demux_dir="01_DORADO_BASECALL/demux/{sample}/"
    params:
        kit_name=config.get("dorado", {}).get("kit_name", "SQK-RNA004-24"),
        docker_image=config.get("dorado", {}).get("docker_image", "docker.1ms.run/nanoporetech/dorado:latest"),
        exec_mode=config.get("dorado", {}).get("exec_mode", config.get("exec_mode", "native"))
    threads: 4
    container:
        lambda wc, output, params: params.docker_image if params.exec_mode == "docker" else None
    log:
        "logs/dorado/{sample}_demux.log"
    shell:
        """
        mkdir -p "$(dirname {output.demux_dir})" "$(dirname {log})"
        dorado demux {input.reads} --kit-name {params.kit_name} \
            --output-dir "$(dirname {output.demux_dir})" >> {log} 2>&1
        """
