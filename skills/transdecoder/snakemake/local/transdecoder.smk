# transdecoder 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/flrnaseq.smk/workflow/rules/transdecoder.smk
# 去掉对 Snakefile 顶部全局变量（SAMPLES / os / directory / config）的依赖：
#   - SAMPLES lambda 输入 -> 路径模板 long_read/{sample}.fasta
#   - config["transdecoder_dir"] -> 规则内输出路径模板 transdecoder/{sample}/...
#   - config["transdecoder"] 参数 -> 规则内显式默认值（与 flrnaseq config.yaml transdecoder 段一致）
#   - docker/container 分支移除（docker_wrapper.py 不再需要），直接调用本地二进制
# 使用前准备 envs/transdecoder.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies:
#     - transdecoder=5.7.1
#     - perl
#     - parallel
# ---------------------------------------------------------------------------

# ---- TransDecoder.LongOrfs：提取候选最长 ORF ------------------------------
rule transdecoder_longorfs:
    input:
        fasta="long_read/{sample}.fasta"
    output:
        dir=directory("transdecoder/{sample}/longorfs")
    params:
        gene_trans_map="",            # config["transdecoder"]["gene_trans_map"]，可选：path/to/gene_trans_map
        extra="-m 50 -G Universal -S --complete_orfs_only",   # config longorfs_extra_params
        version="5.7.1"
    threads: 4
    conda:
        "envs/transdecoder.yaml"
    log:
        "logs/transdecoder/longorfs_{sample}.log"
    message:
        "Running TransDecoder.LongOrfs (v{params.version}) on {input.fasta}"
    shell:
        """
        OUT="$(dirname {output.dir})"
        mkdir -p "$OUT" "$(dirname {log})"

        IN="{input.fasta}"
        BASE_DIR="{output.dir}"

        # 输入为 .gz 时先解压（迁移自 transdecoder_longorfs.py 的 gunzip 逻辑）
        if [[ "$IN" == *.gz ]]; then
            IN_GZ="$IN"
            IN="$OUT/$(basename "$IN_GZ" .gz)"
            gunzip -c "$IN_GZ" > "$IN"
        fi

        # TransDecoder 会创建 <basename>.transdecoder_dir；先清理上次残留（工具无 force 选项）
        CREATED_DIR="$OUT/$(basename "$IN").transdecoder_dir"
        rm -rf "$CREATED_DIR"

        GTM_CMD=""
        if [ -n "{params.gene_trans_map}" ]; then
            GTM_CMD=" --gene_trans_map {params.gene_trans_map}"
        fi

        TransDecoder.LongOrfs -t "$IN" -O "$OUT" $GTM_CMD {params.extra} >> {log} 2>&1

        # 把生成的 transdecoder_dir 拷贝到规则输出目录
        mkdir -p "{output.dir}"
        cp -r "$CREATED_DIR" "{output.dir}"
        """

# ---- TransDecoder.Predict：基于序列组成模型预测最终 CDS -------------------
rule transdecoder_predict:
    input:
        fasta="long_read/{sample}.fasta",
        td_dir="transdecoder/{sample}/longorfs"
    output:
        dir=directory("transdecoder/{sample}/predict"),
        pep="transdecoder/{sample}/predict/{sample}.pep",
        cds="transdecoder/{sample}/predict/{sample}.cds",
        gff3="transdecoder/{sample}/predict/{sample}.gff3",
        bed="transdecoder/{sample}/predict/{sample}.bed"
    params:
        retain_pfam_hits="",          # config["transdecoder"]["retain_pfam_hits"]，可选
        retain_blastp_hits="",        # config["transdecoder"]["retain_blastp_hits"]，可选
        extra="--no_refine_starts",   # config predict_extra_params
        version="5.7.1"
    threads: 8
    conda:
        "envs/transdecoder.yaml"
    log:
        "logs/transdecoder/predict_{sample}.log"
    message:
        "Running TransDecoder.Predict (v{params.version}) on {input.fasta}"
    shell:
        """
        SAMPLE="{wildcards.sample}"
        BASE_DIR="$(dirname {output.dir})"
        mkdir -p "{output.dir}" "$(dirname {log})"

        IN="{input.fasta}"
        if [[ "$IN" == *.gz ]]; then
            IN_GZ="$IN"
            IN="$BASE_DIR/$(basename "$IN_GZ" .gz)"
            gunzip -c "$IN_GZ" > "$IN"
        fi

        # 确保 .transdecoder_dir 存在（迁移自 transdecoder_predict.py：从输入 td_dir 恢复）
        CREATED_DIR="$BASE_DIR/$(basename "$IN").transdecoder_dir"
        if [ ! -d "$CREATED_DIR" ]; then
            cp -r "{input.td_dir}" "$CREATED_DIR"
        fi

        ADDL=""
        if [ -n "{params.retain_pfam_hits}" ]; then
            ADDL="$ADDL --retain_pfam_hits {params.retain_pfam_hits}"
        fi
        if [ -n "{params.retain_blastp_hits}" ]; then
            ADDL="$ADDL --retain_blastp_hits {params.retain_blastp_hits}"
        fi

        TransDecoder.Predict -t "$IN" -O "$BASE_DIR" $ADDL {params.extra} --cpu {threads} >> {log} 2>&1

        # 移动最终产物到规则输出目录（迁移自 transdecoder_predict.py 的 mv 逻辑）
        for EXT in bed cds gff3 pep; do
            SRC="$BASE_DIR/$(basename "$IN").transdecoder.$EXT"
            DEST="{output.dir}/$SAMPLE.$EXT"
            if [ -f "$SRC" ]; then
                mv "$SRC" "$DEST"
            fi
        done

        rm -rf "$CREATED_DIR"
        """
