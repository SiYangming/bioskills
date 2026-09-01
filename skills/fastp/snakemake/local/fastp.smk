# fastp 自维护 Snakemake 规则
# ---------------------------------------------------------------------------
# source_type: custom —— 不依赖官方 snakemake-wrappers 中央缓存，
# 直接调用本地 fastp 二进制（或 conda env：conda: "envs/fastp.yaml"）。
#
# 命令对齐 native 与 custom/subworkflow/fastp_bwa_samtools 编排器约定：
#   fastp -i R1 [-I R2] -o out1 [-O out2] -h report.html -j report.json -w <threads>
#
# 用法：
#   include: "skills/fastp/snakemake/local/fastp.smk"
#   snakemake -j 8 results/fastp/sample1_R1.clean.fastq.gz
#
# config["fastp"] 可选（缺省自动跳过）：
#   fastp:
#     adapter_sequence: "AGATCGGAAGAGCACACGTCTGA"   # R1 3' 接头（IUPAC）
#     detect_adapter_for_pe: true                   # PE 重叠检测（默认 false）
#     qualified_quality_phred: 15
#     unqualified_percent_limit: 40
#     length_required: 15
#     extra: "--cut_front --cut_tail --cut_right 1"  # 额外透传
# ---------------------------------------------------------------------------

# fastp 0.20+ 线程参数为 -w/--thread（-t 已被 --trim_tail1 占用）
rule fastp:
    input:
        r1 = "reads/{sample}_R1.fastq.gz",
        r2 = "reads/{sample}_R2.fastq.gz"
    output:
        out1 = "results/fastp/{sample}_R1.clean.fastq.gz",
        out2 = "results/fastp/{sample}_R2.clean.fastq.gz",
        html = "results/fastp/{sample}_fastp.html",
        json = "results/fastp/{sample}_fastp.json"
    log:
        "results/fastp/logs/fastp_{sample}.log"
    threads: 8
    params:
        adapter_sequence = config.get("fastp", {}).get("adapter_sequence", ""),
        detect_adapter_for_pe = config.get("fastp", {}).get("detect_adapter_for_pe", False),
        qualified_quality_phred = config.get("fastp", {}).get("qualified_quality_phred", None),
        unqualified_percent_limit = config.get("fastp", {}).get("unqualified_percent_limit", None),
        length_required = config.get("fastp", {}).get("length_required", None),
        extra = config.get("fastp", {}).get("extra", "")
    run:
        cmd = [
            "fastp",
            "-i", input.r1, "-I", input.r2,
            "-o", output.out1, "-O", output.out2,
            "-h", output.html, "-j", output.json,
            "-w", str(threads),
        ]
        if params.adapter_sequence:
            cmd += ["--adapter_sequence", params.adapter_sequence]
        if params.detect_adapter_for_pe:
            cmd.append("--detect_adapter_for_pe")
        if params.qualified_quality_phred is not None:
            cmd += ["-q", str(params.qualified_quality_phred)]
        if params.unqualified_percent_limit is not None:
            cmd += ["-u", str(params.unqualified_percent_limit)]
        if params.length_required is not None:
            cmd += ["-l", str(params.length_required)]
        if params.extra:
            cmd += str(params.extra).split()
        shell(" ".join(cmd) + " 2> {log}")

# 单端变体（fastp 也支持 SE）：取消注释并使用
# rule fastp_se:
#     input:
#         r1 = "reads/{sample}_R1.fastq.gz"
#     output:
#         out1 = "results/fastp/{sample}_R1.clean.fastq.gz",
#         html = "results/fastp/{sample}_fastp.html",
#         json = "results/fastp/{sample}_fastp.json"
#     log:
#         "results/fastp/logs/fastp_{sample}.log"
#     threads: 4
#     run:
#         shell("fastp -i {input.r1} -o {output.out1} "
#               "-h {output.html} -j {output.json} -w {threads} 2> {log}")
