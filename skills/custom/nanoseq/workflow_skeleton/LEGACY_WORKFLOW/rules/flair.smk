rule bam2bed12:
    input:
        bam = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "SORTED_BAM", "{sample}.sorted.bam"),
        summary = os.path.join(config["output_dir"], "01_MINIMAP2_ALIGN", "ALIGNMENT_STATS_SUMMARY.txt")
    output:
        bed12 = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "BED12", "{sample}.bed12")
    log:
        os.path.join(config["output_dir"], "LOGS", "FLAIR_CONSENSUS_{sample}_bam2bed12.log")
    params:
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["flair"]["docker_image"],
        root_dir = os.getcwd()
    conda:
        "../envs/flair.yaml"
    container:
        config["flair"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.bed12})"
        mkdir -p "$OUTDIR"
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd bash -lc 'bedtools bamtobed -bed12 -i {input.bam} | python3 workflow/scripts/bed12_add_trailing_commas.py > {output.bed12}' 2> {log}
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd bedtools --version 2>> {log} | head -n1 || echo unknown)
        else
            bedtools bamtobed -bed12 -i {input.bam} | python3 workflow/scripts/bed12_add_trailing_commas.py > {output.bed12} 2> {log}
            VER=$(bedtools --version 2>> {log} | head -n1 || echo unknown)
        fi
        echo "bedtools_version: $VER" >> {log}
        """

rule flair_annotate:
    input:
        bed12 = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "BED12", "{sample}.bed12"),
        gtf = get_gtf
    output:
        annotated_bed = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "ANNOTATED_BED", "{sample}.annotated.bed")
    log:
        os.path.join(config["output_dir"], "LOGS", "FLAIR_CONSENSUS_{sample}_flair_annotate.log")
    params:
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["flair"]["docker_image"],
        root_dir = os.getcwd()
    conda:
        "../envs/flair.yaml"
    container:
        config["flair"]["docker_image"]
    shell:
        """
        OUTDIR="$(dirname {output.annotated_bed})"
        mkdir -p "$OUTDIR"
        # identify_gene_isoform requires positional arguments: bed gtf outfilename
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd python3 -m flair.identify_gene_isoform {input.bed12} {input.gtf} {output.annotated_bed} > {log} 2>&1
        else
            python3 -m flair.identify_gene_isoform {input.bed12} {input.gtf} {output.annotated_bed} > {log} 2>&1
        fi
        """

rule flair_collapse:
    input:
        annotated_bed = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "ANNOTATED_BED", "{sample}.annotated.bed"),
        fastq = get_fastq,
        genome = get_ref_fasta,
        gtf = get_gtf
    output:
        consensus = os.path.join(config["output_dir"], "02_FLAIR_CONSENSUS", "CONSENSUS_FASTA", "{sample}.flair.collapse.fasta")
    log:
        os.path.join(config["output_dir"], "LOGS", "FLAIR_CONSENSUS_{sample}_flair_collapse.log")
    params:
        threads = config["flair"]["threads"],
        args = config["flair"]["args"],
        out_prefix = lambda wildcards, output: output.consensus.replace(".flair.collapse.fasta", ""),
        exec_mode = config.get("exec_mode", "native"),
        docker_image = config["flair"]["docker_image"],
        root_dir = os.getcwd(),
        bin_path = config["flair"].get("flair_bin", "")
    threads: config["flair"]["threads"]
    conda:
        "../envs/flair.yaml"
    container:
        config["flair"]["docker_image"]
    shell:
        """
        if [ "{params.exec_mode}" = "docker" ]; then
            python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd flair collapse -q {input.annotated_bed} -g {input.genome} -r {input.fastq} -o {params.out_prefix} -t {threads} -f {input.gtf} {params.args} 2> {log}
            VER=$(python3 workflow/scripts/docker_wrapper.py --image {params.docker_image} --volume {params.root_dir}:{params.root_dir} --workdir {params.root_dir} --cmd flair --version 2>> {log} | head -n1 || echo unknown)
            cp {params.out_prefix}.isoforms.fa {output.consensus}
        elif [ -n "{params.bin_path}" ]; then
            "{params.bin_path}" collapse -q {input.annotated_bed} -g {input.genome} -r {input.fastq} -o {params.out_prefix} -t {threads} -f {input.gtf} {params.args} 2> {log}
            VER=$("{params.bin_path}" --version 2>> {log} | head -n1 || echo unknown)
            cp {params.out_prefix}.isoforms.fa {output.consensus}
        else
            flair collapse -q {input.annotated_bed} -g {input.genome} -r {input.fastq} -o {params.out_prefix} -t {threads} -f {input.gtf} {params.args} 2> {log}
            VER=$(flair --version 2>> {log} | head -n1 || echo unknown)
            cp {params.out_prefix}.isoforms.fa {output.consensus}
        fi
        echo "flair_version: $VER" >> {log}
        """
