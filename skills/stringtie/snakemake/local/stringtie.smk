# stringtie 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# 迁移自：snakemake.smk/nanoseq.smk/nanoseq.sh/run_stringtie.sh
# 去掉 nohup/PID/LOCK 后台运行封装、绝对路径（./bin/stringtie-3.0.3.Linux_x86_64/stringtie）
# 与 GNU parallel 依赖；三段链路拆为三个 rule，命令参数内联。
# 使用前准备 envs/stringtie.yaml：
#   channels: [conda-forge, bioconda]
#   dependencies: [stringtie=3.0.3]
# ---------------------------------------------------------------------------

# Step 1: stringtie 组装（long-read 模式，nanoseq 参数内联）
rule stringtie_assemble:
    input:
        bam="alignment/{sample}.sorted.bam",
        gtf=config.get("gtf_annotation", "ref/gencode.v49.annotation.gtf")
    output:
        gtf="assembled/{sample}.stringtie.gtf"
    params:
        stringtie_bin="stringtie",
        min_transcript_len=200
    threads: 8
    conda:
        "envs/stringtie.yaml"
    log:
        "logs/stringtie/{sample}_stringtie.log"
    shell:
        """
        mkdir -p "$(dirname {output.gtf})" "$(dirname {log})"
        "{params.stringtie_bin}" {input.bam} \
            --conservative -L -R \
            -G {input.gtf} \
            -o {output.gtf} \
            -l {wildcards.sample} \
            -m {params.min_transcript_len} \
            -p {threads} >> {log} 2>&1
        test -s {output.gtf}
        """

# Step 2: 坐标修复（awk 内联，$4>$5 交换；纯文本，无需 stringtie）
rule stringtie_fix_gtf:
    input:
        gtf="assembled/{sample}.stringtie.gtf"
    output:
        gtf="assembled/fixed/{sample}.stringtie.fixed.gtf"
    threads: 2
    log:
        "logs/stringtie/{sample}_fix_gtf.log"
    shell:
        """
        mkdir -p "$(dirname {output.gtf})" "$(dirname {log})"
        awk -F'\\t' -v OFS='\\t' '/^#/{{print;next}} $4>$5{{t=$4;$4=$5;$5=t}} {{print}}' \
            {input.gtf} > {output.gtf} 2>> {log}
        test -s {output.gtf}
        """

# Step 3: stringtie --merge 多样本非冗余合并（GTF 列表由规则收集）
rule stringtie_merge:
    input:
        gtf_list="stringtie_gtf_list.txt",
        gtf=config.get("gtf_annotation", "ref/gencode.v49.annotation.gtf")
    output:
        gtf="merged/stringtie_merged_nonredundant.gtf"
    params:
        stringtie_bin="stringtie",
        label="MSTRG",
        min_transcript_len=200
    threads: 4
    conda:
        "envs/stringtie.yaml"
    log:
        "logs/stringtie/stringtie_merge.log"
    shell:
        """
        mkdir -p "$(dirname {output.gtf})" "$(dirname {log})"
        find assembled/fixed -name "*.fixed.gtf" -size +0 > {input.gtf_list}
        "{params.stringtie_bin}" --merge \
            -G {input.gtf} \
            -o {output.gtf} \
            -l {params.label} \
            -m {params.min_transcript_len} \
            {input.gtf_list} >> {log} 2>&1
        test -s {output.gtf}
        """
