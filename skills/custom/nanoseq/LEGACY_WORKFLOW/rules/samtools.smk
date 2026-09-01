rule samtools_sort:
    input:
        sam = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "BAM", "{sample}.sam")
    output:
        bam = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam"),
        bai = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam.bai")
    log:
        os.path.join(config["output_dir"], "LOGS", "MINIMAP2_ALIGN_{sample}_samtools_sort.log")
    threads: config["samtools"]["threads"]
    params:
        runner = get_runner("samtools"),
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["samtools"]["docker_image"],
        bin_path = config["samtools"].get("samtools_bin", ""),
        root_dir = os.getcwd()
    conda:
        "../envs/samtools.yaml"
    container:
        config["samtools"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.bam})"
        mkdir -p "$OUTDIR"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd samtools sort -@ {threads} -o {output.bam} {input.sam} 2> {log}
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd samtools index -@ {threads} {output.bam} 2>> {log}
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd samtools --version 2>> {log} | head -n1 || echo unknown)
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" sort -@ {threads} -o {output.bam} {input.sam} 2> {log}
            "{params.bin_path}" index -@ {threads} {output.bam} 2>> {log}
            VER=$("{params.bin_path}" --version 2>> {log} | head -n1)
        else
            samtools sort -@ {threads} -o {output.bam} {input.sam} 2> {log}
            samtools index -@ {threads} {output.bam} 2>> {log}
            VER=$(samtools --version 2>> {log} | head -n1)
        fi
        echo "samtools_version: $VER" >> {log}
        """

rule samtools_flagstat:
    input:
        bam = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam"),
        bai = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam.bai") # Ensure index exists
    output:
        txt = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "FLAGSTAT", "{sample}.flagstat.txt")
    log:
        os.path.join(config["output_dir"], "LOGS", "MINIMAP2_ALIGN_{sample}_flagstat.log")
    params:
        runner = get_runner("samtools"),
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["samtools"]["docker_image"],
        bin_path = config["samtools"].get("samtools_bin", ""),
        root_dir = os.getcwd()
    conda:
        "../envs/samtools.yaml"
    container:
        config["samtools"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.txt})"
        mkdir -p "$OUTDIR"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd samtools flagstat {input.bam} > {output.txt} 2> {log}
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" flagstat {input.bam} > {output.txt} 2> {log}
        else
            samtools flagstat {input.bam} > {output.txt} 2> {log}
        fi
        """

rule alignment_summary:
    input:
        expand(os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "FLAGSTAT", "{sample}.flagstat.txt"), sample=SAMPLES.keys())
    output:
        summary = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "ALIGNMENT_STATS_SUMMARY.txt")
    log:
        os.path.join(config["output_dir"], "LOGS", "MINIMAP2_ALIGN_alignment_summary.log")
    conda:
        "../envs/python.yaml"
    script:
        "../scripts/alignment_summary.py"
