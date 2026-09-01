ORFANAGE_DIR = config["orfanage_dir"]

rule orfanage:
    input:
        templates = lambda wildcards: [SAMPLES.loc[wildcards.sample, "genome_gtf"]],
        query_dir = os.path.join(TRANSDECODER_DIR, "{sample}", "predict"),
        reference = lambda wildcards: SAMPLES.loc[wildcards.sample, "genome_fasta"]
    output:
        dir = directory(os.path.join(ORFANAGE_DIR, "{sample}"))
    params:
        extra = config["orfanage"]["extra_params"],
        mode = config["orfanage"]["mode"],
        version = config["orfanage"]["version"]            
    conda: "../envs/orfanage.yaml"
    container:
        config["containers"]["orfanage"]
    log:
        os.path.join(config["output_dir"], "LOGS", "orfanage_{sample}.log")
    message:
        "Running ORFanage (v{params.version}) on {input.query_dir}"
    script:
        "../scripts/orfanage.py"
