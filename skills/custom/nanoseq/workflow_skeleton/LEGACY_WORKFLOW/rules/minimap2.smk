rule minimap2_align:
    input:
        fastq = get_fastq,
        ref = get_ref_fasta
    output:
        sam = temp(os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "BAM", "{sample}.sam"))
    log:
        os.path.join(config["output_dir"], "LOGS", "MINIMAP2_ALIGN_{sample}_minimap2.log")
    params:
        args = config["minimap2"]["args"],
        runner = get_runner("minimap2"),
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["minimap2"]["docker_image"],
        bin_path = config["minimap2"].get("minimap2_bin", ""),
        root_dir = os.getcwd()
    threads: config["minimap2"]["threads"]
    conda:
        "../envs/minimap2.yaml"
    container:
        config["minimap2"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.sam})"
        mkdir -p "$OUTDIR"
        ARGS="{params.args} -t {threads} {input.ref} {input.fastq}"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd minimap2 $ARGS > {output.sam} 2> {log}
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd minimap2 --version 2>> {log} | head -n1 || echo unknown)
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" $ARGS > {output.sam} 2> {log}
            VER=$("{params.bin_path}" --version 2>> {log} | head -n1)
        else
            minimap2 $ARGS > {output.sam} 2> {log}
            VER=$(minimap2 --version 2>> {log} | head -n1)
        fi
        echo "minimap2_version: $VER" >> {log}
        """
