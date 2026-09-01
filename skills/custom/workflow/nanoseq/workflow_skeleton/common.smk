import pandas as pd
import os
from snakemake.utils import validate

# Parse configuration
configfile: "config.yaml"

# Validate configuration (optional, if schema exists)
# validate(config, schema="config/config.schema.yaml")

# Parse samplesheet
samplesheet_path = config.get("samplesheet", "test/samplesheet_local.csv")
# validate(pd.read_csv(samplesheet_path), schema="config/samples.schema.yaml")

samples_df = pd.read_csv(samplesheet_path).fillna("")

# Create SAMPLES dictionary
SAMPLES = {}
for index, row in samples_df.iterrows():
    sample_id = f"{row['group']}-rep{row['replicate']}"
    
    # Determine input fastq
    input_path = row['input_file']
    if os.path.isdir(input_path):
        # Assumption: fastq is inside 'fastq' subdir or directly in dir
        # Based on exploration: {input_path}/fastq/{sample_id}.fastq.gz
        fastq_candidate = os.path.join(input_path, "fastq", f"{sample_id}.fastq.gz")
        if os.path.exists(fastq_candidate):
            fastq_file = fastq_candidate
        else:
            # Fallback: check if any fastq in dir
            fastqs = [f for f in os.listdir(input_path) if f.endswith(".fastq.gz")]
            if fastqs:
                fastq_file = os.path.join(input_path, fastqs[0])
            else:
                 # Fallback 2: maybe input_path IS the prefix or we just assume the pattern
                 fastq_file = fastq_candidate
    else:
        fastq_file = input_path

    SAMPLES[sample_id] = {
        "fastq": fastq_file,
        "fasta": row['fasta'],
        "gtf": row['gtf'],
        "input_file": row['input_file']
    }

GROUPS = {}
for index, row in samples_df.iterrows():
    g = str(row['group'])
    sample_id = f"{row['group']}-rep{row['replicate']}"
    GROUPS.setdefault(g, []).append(sample_id)

# Helper functions
def get_fastq(wildcards):
    fq = SAMPLES[wildcards.sample].get("fastq", "")
    if fq and os.path.exists(fq):
        return fq
    # Fallback: if fastq missing, try sample-specific fasta
    fa = SAMPLES[wildcards.sample].get("fasta", "")
    if fa and os.path.exists(fa):
        return fa
    # Last resort: use global genome_fasta (not ideal for alignment; ensures rule does not crash)
    return config["genome_fasta"]

def get_ref_fasta(wildcards):
    # Prefer sample-specific fasta, else config
    if SAMPLES[wildcards.sample]["fasta"]:
        return SAMPLES[wildcards.sample]["fasta"]
    return config["genome_fasta"]

def get_gtf(wildcards):
    if SAMPLES[wildcards.sample]["gtf"]:
        return SAMPLES[wildcards.sample]["gtf"]
    return config["gtf_annotation"]

def get_runner(tool_key):
    mode = config.get("exec_mode", "native")
    if mode == "docker":
        image = config[tool_key]["docker_image"]
        wd = os.getcwd()
        return f"python3 workflow/scripts/docker_wrapper.py --image {image} --volume {wd}:{wd} --workdir {wd} --"
    return ""
