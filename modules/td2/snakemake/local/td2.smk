TD2_DIR = config["td2_dir"]

rule td2_longorfs:
    input:
        fasta = lambda wildcards: SAMPLES.loc[wildcards.sample, "long_read_fasta"]
    output:
        dir = directory(os.path.join(TD2_DIR, "{sample}", "longorfs")),
        pep = os.path.join(TD2_DIR, "{sample}", "longorfs", "longest_orfs.pep"),
        gff3 = os.path.join(TD2_DIR, "{sample}", "longorfs", "longest_orfs.gff3"),
        cds = os.path.join(TD2_DIR, "{sample}", "longorfs", "longest_orfs.cds")
    params:
        gene_trans_map = config["td2"]["gene_trans_map"],
        extra = config["td2"]["longorfs_extra_params"],
        version = config["td2"]["version"]
    conda: "../envs/td2.yaml"
    container:
        config["containers"]["td2"]
    log:
        os.path.join(config["output_dir"], "LOGS", "td2_longorfs_{sample}.log")
    threads:
        config["threads"]
    message:
        "Running TD2.LongOrfs (v{params.version}) on {input.fasta}"
    script:
        "../scripts/td2_longorfs.py"

rule td2_predict:
    input:
        fasta = lambda wildcards: SAMPLES.loc[wildcards.sample, "long_read_fasta"],
        td_dir = os.path.join(TD2_DIR, "{sample}", "longorfs")
    output:
        # Final TD2 outputs
        dir = directory(os.path.join(TD2_DIR, "{sample}", "predict")),
        pep = os.path.join(TD2_DIR, "{sample}", "predict", "{sample}.pep"),
        gff3 = os.path.join(TD2_DIR, "{sample}", "predict", "{sample}.gff3"),
        cds = os.path.join(TD2_DIR, "{sample}", "predict", "{sample}.cds"),
        bed = os.path.join(TD2_DIR, "{sample}", "predict", "{sample}.bed"),
    params:
        retain_mmseqs_hits = config["td2"]["retain_mmseqs_hits"],
        retain_blastp_hits = config["td2"]["retain_blastp_hits"],
        retain_hmmer_hits = config["td2"]["retain_hmmer_hits"],
        extra = config["td2"]["predict_extra_params"],
        version = config["td2"]["version"]
    conda: "../envs/td2.yaml"
    container:
        config["containers"]["td2"]
    log:
        os.path.join(config["output_dir"], "LOGS", "td2_predict_{sample}.log")
    threads:
        config["threads"]
    message:
        "Running TD2.Predict (v{params.version}) on {input.fasta}"
    script:
        "../scripts/td2_predict.py"
