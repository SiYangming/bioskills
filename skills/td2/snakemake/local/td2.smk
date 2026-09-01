# td2 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/flrnaseq.smk/workflow/rules/td2.smk
# 去掉对 Snakefile 顶部全局变量（SAMPLES / os / directory / config）的依赖：
#   - SAMPLES lambda 输入 -> 路径模板 long_read/{sample}.fasta
#   - config["td2_dir"] -> 规则内输出路径模板 td2/{sample}/...
#   - config["td2"] 参数 -> 规则内显式默认值（与 flrnaseq config.yaml td2 段一致）
#   - docker/container 分支移除（docker_wrapper.py 不再需要），直接调用本地二进制
# 使用前准备 envs/td2.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies:
#     - td2=1.0.6
# ---------------------------------------------------------------------------

# ---- TD2.LongOrfs：提取候选最长 ORF ---------------------------------------
# 注意：TD2 的 -O 即最终输出目录（不同于 TransDecoder 会建子目录）。
rule td2_longorfs:
    input:
        fasta="long_read/{sample}.fasta"
    output:
        dir=directory("td2/{sample}/longorfs"),
        pep="td2/{sample}/longorfs/longest_orfs.pep",
        gff3="td2/{sample}/longorfs/longest_orfs.gff3",
        cds="td2/{sample}/longorfs/longest_orfs.cds"
    params:
        gene_trans_map="",            # config["td2"]["gene_trans_map"]，可选：path/to/gene_trans_map
        extra="-m 90 -M 90 -G 1 -S --alt-start --all-stopless",   # config longorfs_extra_params
        version="1.0.6"
    threads: 8
    conda:
        "envs/td2.yaml"
    log:
        "logs/td2/longorfs_{sample}.log"
    message:
        "Running TD2.LongOrfs (v{params.version}) on {input.fasta}"
    shell:
        """
        mkdir -p "{output.dir}" "$(dirname {log})"

        IN="{input.fasta}"
        # 输入为 .gz 时先解压（迁移自 td2_longorfs.py 的 gunzip 逻辑）
        if [[ "$IN" == *.gz ]]; then
            IN_GZ="$IN"
            IN="{output.dir}/$(basename "$IN_GZ" .gz)"
            gunzip -c "$IN_GZ" > "$IN"
        fi

        GTM_CMD=""
        if [ -n "{params.gene_trans_map}" ]; then
            GTM_CMD=" --gene-trans-map {params.gene_trans_map}"
        fi

        # -O 直接指向规则输出目录（TD2 语义）
        TD2.LongOrfs -t "$IN" -O "{output.dir}" $GTM_CMD {params.extra} --threads {threads} >> {log} 2>&1
        """

# ---- TD2.Predict：基于 PSAURON + 长度模型预测最终 CDS ---------------------
rule td2_predict:
    input:
        fasta="long_read/{sample}.fasta",
        td_dir="td2/{sample}/longorfs"
    output:
        dir=directory("td2/{sample}/predict"),
        pep="td2/{sample}/predict/{sample}.pep",
        gff3="td2/{sample}/predict/{sample}.gff3",
        cds="td2/{sample}/predict/{sample}.cds",
        bed="td2/{sample}/predict/{sample}.bed"
    params:
        retain_mmseqs_hits="",        # config["td2"]["retain_mmseqs_hits"]，可选
        retain_blastp_hits="",        # config["td2"]["retain_blastp_hits"]，可选
        retain_hmmer_hits="",         # config["td2"]["retain_hmmer_hits"]，可选
        extra="--psauron-all-frame",  # config predict_extra_params
        version="1.0.6"
    threads: 8
    conda:
        "envs/td2.yaml"
    log:
        "logs/td2/predict_{sample}.log"
    message:
        "Running TD2.Predict (v{params.version}) on {input.fasta}"
    shell:
        """
        SAMPLE="{wildcards.sample}"
        mkdir -p "{output.dir}" "$(dirname {log})"

        IN="{input.fasta}"
        if [[ "$IN" == *.gz ]]; then
            IN_GZ="$IN"
            IN="{output.dir}/$(basename "$IN_GZ" .gz)"
            gunzip -c "$IN_GZ" > "$IN"
        fi

        ADDL=""
        if [ -n "{params.retain_mmseqs_hits}" ]; then
            ADDL="$ADDL --retain-mmseqs-hits {params.retain_mmseqs_hits}"
        fi
        if [ -n "{params.retain_blastp_hits}" ]; then
            ADDL="$ADDL --retain-blastp-hits {params.retain_blastp_hits}"
        fi
        if [ -n "{params.retain_hmmer_hits}" ]; then
            ADDL="$ADDL --retain-hmmer-hits {params.retain_hmmer_hits}"
        fi

        # -O 指向 LongOrfs 产物目录（td_dir），TD2 在 cwd 生成 <basename>.TD2.{ext}
        TD2.Predict -t "$IN" -O "{input.td_dir}" $ADDL {params.extra} --threads {threads} >> {log} 2>&1

        # 移动最终产物到规则输出目录（迁移自 td2_predict.py 的 mv 逻辑）
        for EXT in bed cds gff3 pep; do
            SRC="$(basename "$IN").TD2.$EXT"
            DEST="{output.dir}/$SAMPLE.$EXT"
            if [ -f "$SRC" ]; then
                mv "$SRC" "$DEST"
            fi
        done
        """
