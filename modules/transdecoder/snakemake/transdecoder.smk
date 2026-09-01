TRANSDECODER_DIR = config["transdecoder_dir"]
rule transdecoder_longorfs:
    input:
        fasta = lambda wildcards: SAMPLES.loc[wildcards.sample, "long_read_fasta"]
    output:
        dir = directory(os.path.join(TRANSDECODER_DIR, "{sample}", "longorfs"))
    params:
        gene_trans_map = config["transdecoder"]["gene_trans_map"],
        extra = config["transdecoder"]["longorfs_extra_params"],
        version = config["transdecoder"]["version"]
    conda: "../envs/transdecoder.yaml"
    container:
        config["containers"]["transdecoder"]
    log:
        os.path.join(config["output_dir"], "LOGS", "transdecoder_longorfs_{sample}.log")
    threads:
        config["threads"]
    message:
        "Running TransDecoder.LongOrfs (v{params.version}) on {input.fasta}"
    script: 
        "../scripts/transdecoder_longorfs.py"

rule transdecoder_predict:
    input:
        fasta = lambda wildcards: SAMPLES.loc[wildcards.sample, "long_read_fasta"],
        td_dir = os.path.join(TRANSDECODER_DIR, "{sample}", "longorfs")
    output:
        dir = directory(os.path.join(TRANSDECODER_DIR, "{sample}", "predict"))
    params:
        retain_pfam_hits = config["transdecoder"]["retain_pfam_hits"],
        retain_blastp_hits = config["transdecoder"]["retain_blastp_hits"],
        extra = config["transdecoder"]["predict_extra_params"],
        version = config["transdecoder"]["version"]
    conda: "../envs/transdecoder.yaml"
    container:
        config["containers"]["transdecoder"]
    log:
        os.path.join(config["output_dir"], "LOGS", "transdecoder_predict_{sample}.log")
    threads:
        config["threads"]
    message:
        "Running TransDecoder.Predict (v{params.version}) on {input.fasta}"
    script: 
        "../scripts/transdecoder_predict.py"
