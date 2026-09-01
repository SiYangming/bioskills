# gstama merge Snakemake rule（从 isoseq.smk/workflow/rules/gstama.smk 迁移）
#
# 迁移说明：去掉 docker_run 分支与 GSTAMA_DOCKER_IMAGE 容器配置；路径通过 config 可覆盖。

GSTAMA_MERGE_BIN = config.get("gstama", {}).get("gstama_merge_bin", "tama_merge.py")
GSTAMA_MERGE_ARGS = config.get("gstama", {}).get(
    "merge_args", "-a 100 -z 100 -m 20 -d merge_dup")

rule gstama_merge:
    """TAMA merge 合并多个转录本集合（空 filelist 自动跳过并 touch 输出）。"""
    input:
        filelist="results/gstama_filelist/filelist.tsv"
    output:
        bed="results/gstama_merge/merged.bed",
        versions="results/gstama_merge/versions.yml"
    params:
        gstama_merge_bin=GSTAMA_MERGE_BIN,
        args=GSTAMA_MERGE_ARGS,
        prefix=lambda wildcards, output: output.bed.replace(".bed", "")
    threads: 1
    log:
        "logs/gstama_merge.log"
    shell:
        """
        mkdir -p "$(dirname {output.bed})" "$(dirname {log})"

        if [ ! -s {input.filelist} ]; then
            echo "Filelist is empty, skipping merge"
            touch {output.bed}
            echo "tama_merge: skipped" > {output.versions}
            exit 0
        fi

        {params.gstama_merge_bin} -f {input.filelist} -p "{params.prefix}" \
            {params.args} >> {log} 2>&1

        echo "tama_merge: 1.0.4" > {output.versions}
        """
