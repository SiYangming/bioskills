ORFFINDER_DIR = config["orffinder_dir"]
OUTFMT = config["orffinder"]["outfmt"]
_SUFFIX_MAP = config["orffinder"]["suffix_map"]
ORFFINDER_SUFFIX = _SUFFIX_MAP[OUTFMT]

rule orffinder:
    input:
        fasta = lambda wildcards: SAMPLES.loc[wildcards.sample, "long_read_fasta"]
    output:
        file = os.path.join(ORFFINDER_DIR, "{sample}" + ORFFINDER_SUFFIX)
    params:
        outfmt = config["orffinder"]["outfmt"],
        extra = config["orffinder"]["extra_params"]
    conda: "../envs/orffinder.yaml"
    container:
        config["containers"]["orffinder"]
    log:
        os.path.join(config["output_dir"], "LOGS", "orffinder_{sample}.log")
    threads:
        config["threads"]
    script:
        "../scripts/orffinder.py"
