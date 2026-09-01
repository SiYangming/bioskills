rule stringtie_assemble:
    input:
        bam = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam"),
        consensus = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "CONSENSUS_FASTA", "{sample}.flair.collapse.fasta"),
        gtf = get_gtf
    output:
        gtf = temp(os.path.join(config["output_dir"], "03_STRINGTIE", "ASSEMBLED_GTF", "{sample}.stringtie.gtf"))
    log:
        os.path.join(config["output_dir"], "LOGS", "STRINGTIE_{sample}_stringtie.log")
    params:
        threads = config["stringtie"]["threads"],
        min_len = config["stringtie"]["min_transcript_len"],
        args = config["stringtie"]["args"],
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["stringtie"]["docker_image"],
        root_dir = os.getcwd(),
        bin_path = config["stringtie"].get("stringtie_bin", "")
    threads: config["stringtie"]["threads"]
    conda:
        "../envs/stringtie.yaml"
    container:
        config["stringtie"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.gtf})"
        mkdir -p "$OUTDIR"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd stringtie {input.bam} {params.args} -G {input.gtf} -o {output.gtf} -l {wildcards.sample} -m {params.min_len} -p {threads} > {log} 2>&1
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd stringtie --version 2>> {log} | head -n1 || echo unknown)
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" {input.bam} {params.args} -G {input.gtf} -o {output.gtf} -l {wildcards.sample} -m {params.min_len} -p {threads} > {log} 2>&1
            VER=$("{params.bin_path}" --version 2>> {log} | head -n1 || echo unknown)
        else
            stringtie {input.bam} {params.args} -G {input.gtf} -o {output.gtf} -l {wildcards.sample} -m {params.min_len} -p {threads} > {log} 2>&1
            VER=$(stringtie --version 2>> {log} | head -n1 || echo unknown)
        fi
        echo "stringtie_version: $VER" >> {log}
        """

rule fix_gtf:
    input:
        gtf = os.path.join(config["output_dir"], "03_STRINGTIE", "ASSEMBLED_GTF", "{sample}.stringtie.gtf")
    output:
        fixed_gtf = os.path.join(config["output_dir"], "03_STRINGTIE", "ASSEMBLED_GTF", "FIXED_GTF", "{sample}.stringtie.fixed.gtf")
    log:
        os.path.join(config["output_dir"], "LOGS", "STRINGTIE_{sample}_fix_gtf.log")
    params:
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["stringtie"]["docker_image"],
        root_dir = os.getcwd()
    conda:
        "../envs/stringtie.yaml"
    container:
        config["stringtie"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.fixed_gtf})"
        mkdir -p "$OUTDIR"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd bash -lc 'awk -F\"\\t\" -v OFS=\"\\t\" -f workflow/scripts/fix_gtf.awk {input.gtf} > {output.fixed_gtf}' 2> {log}
        else
            awk -F'\\t' -v OFS='\\t' -f workflow/scripts/fix_gtf.awk {input.gtf} > {output.fixed_gtf} 2> {log}
        fi
        """

rule stringtie_merge:
    input:
        gtfs = expand(os.path.join(config["output_dir"], "03_STRINGTIE", "ASSEMBLED_GTF", "FIXED_GTF", "{sample}.stringtie.fixed.gtf"), sample=SAMPLES.keys()),
        gtf = config["gtf_annotation"]
    output:
        merged_gtf = os.path.join(config["output_dir"], "03_STRINGTIE", "MERGED_GTF", "stringtie_merged_nonredundant.gtf"),
        gtf_list = os.path.join(config["output_dir"], "03_STRINGTIE", "GTF_LIST.txt")
    log:
        os.path.join(config["output_dir"], "LOGS", "STRINGTIE_stringtie_merge.log")
    params:
        min_len = config["stringtie"]["min_transcript_len"],
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["stringtie"]["docker_image"],
        root_dir = os.getcwd(),
        bin_path = config["stringtie"].get("stringtie_bin", "")
    conda:
        "../envs/stringtie.yaml"
    container:
        config["stringtie"]["docker_image"]
    shell:
        """
        ls {input.gtfs} > {output.gtf_list}
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd stringtie --merge -G {input.gtf} -o {output.merged_gtf} -l MSTRG -m {params.min_len} {output.gtf_list} > {log} 2>&1
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd stringtie --version 2>> {log} | head -n1 || echo unknown)
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" --merge -G {input.gtf} -o {output.merged_gtf} -l MSTRG -m {params.min_len} {output.gtf_list} > {log} 2>&1
            VER=$("{params.bin_path}" --version 2>> {log} | head -n1 || echo unknown)
        else
            stringtie --merge -G {input.gtf} -o {output.merged_gtf} -l MSTRG -m {params.min_len} {output.gtf_list} > {log} 2>&1
            VER=$(stringtie --version 2>> {log} | head -n1 || echo unknown)
        fi
        echo "stringtie_version: $VER" >> {log}
        """
