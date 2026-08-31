# pbccs 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/isoseq.smk/workflow/rules/pbccs.smk
# 去掉对 workflow/lib/helpers.py 的全局依赖（sample_to_bam / docker_run / LOG_DIR）：
#   - 输入改为路径模板 subreads/{sample}.subreads.bam
#   - docker 分支移除，直接调用本地 ccs 二进制
#   - log 目录由规则内 $(dirname {log}) 创建
# 使用前准备 envs/pbccs.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [pbccs=6.4.0]
# ---------------------------------------------------------------------------
rule pbccs:
    input:
        bam="subreads/{sample}.subreads.bam"
    output:
        bam="ccs/{sample}/{sample}.chunk{n}.bam",
        pbi="ccs/{sample}/{sample}.chunk{n}.bam.pbi",
        report="ccs/{sample}/{sample}.chunk{n}.report.txt",
        report_json="ccs/{sample}/{sample}.chunk{n}.report.json",
        metrics="ccs/{sample}/{sample}.chunk{n}.metrics.json.gz"
    params:
        min_rq=0.9,
        min_passes=3,
        min_snr=2.5,
        min_length=10,
        max_length=50000,
        top_passes=60,
        chunk_total=4,
        ccs_bin="ccs"
    threads: 8
    conda:
        "envs/pbccs.yaml"
    log:
        "logs/ccs/{sample}_chunk{n}.log"
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        mkdir -p "$OUTDIR" "$(dirname {log})"

        IN="{input.bam}"
        OUT="{output.bam}"
        REP="{output.report}"
        REPJSON="{output.report_json}"
        METRICS="{output.metrics}"

        # ccs <in> <out> --report-file --report-json --metrics-json --chunk N/TOTAL
        #   --min-rq --min-passes --min-snr --min-length --max-length --top-passes -j
        ARGS="$IN $OUT --report-file $REP --report-json $REPJSON --metrics-json $METRICS --chunk {wildcards.n}/{params.chunk_total} --min-rq {params.min_rq} --min-passes {params.min_passes} --min-snr {params.min_snr} --min-length {params.min_length} --max-length {params.max_length} --top-passes {params.top_passes} -j {threads}"

        "{params.ccs_bin}" $ARGS >> {log} 2>&1
        """
