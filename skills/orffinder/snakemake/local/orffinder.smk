# orffinder 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/flrnaseq.smk/workflow/rules/orffinder.smk
# 去掉对 Snakefile 顶部全局变量（SAMPLES / os / directory / config）的依赖：
#   - SAMPLES lambda 输入 -> 路径模板 long_read/{sample}.fasta
#   - config["orffinder_dir"] / suffix_map -> 规则内输出路径模板
#   - config["orffinder"] 参数 -> 规则内显式默认值（与 flrnaseq config.yaml orffinder 段一致）
#   - docker/container 分支移除（docker_wrapper.py 不再需要），直接调用本地二进制
# 使用前准备 envs/orffinder.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies:
#     - orffinder=0.4.3
# ---------------------------------------------------------------------------

# outfmt -> 输出后缀（flrnaseq config.yaml suffix_map）
#   0: "_orf.fa"（ORFs FASTA）  1: "_cds.fa"（CDS FASTA）
#   2: ".asn1"（Text ASN.1，默认）  3: ".ft"（Feature table）
rule orffinder:
    input:
        fasta="long_read/{sample}.fasta"
    output:
        file="orffinder/{sample}.asn1"      # outfmt=2 默认后缀；改 outfmt 时按 suffix_map 调整
    params:
        outfmt=2,                            # config["orffinder"]["outfmt"]
        extra="-s 2 -ml 30"                  # config orffinder extra_params
    conda:
        "envs/orffinder.yaml"
    log:
        "logs/orffinder/orffinder_{sample}.log"
    shell:
        """
        mkdir -p "$(dirname {output.file})" "$(dirname {log})"

        IN="{input.fasta}"
        # 输入为 .gz 时先解压（迁移自 orffinder.py 的 gunzip 逻辑）
        if [[ "$IN" == *.gz ]]; then
            IN_GZ="$IN"
            IN="$(dirname {output.file})/$(basename "$IN_GZ" .gz)"
            gunzip -c "$IN_GZ" > "$IN"
        fi

        # ORFfinder -in <fasta> -out <file> -outfmt <int> [extra]
        ORFfinder -in "$IN" -out {output.file} -outfmt {params.outfmt} {params.extra} >> {log} 2>&1
        """
