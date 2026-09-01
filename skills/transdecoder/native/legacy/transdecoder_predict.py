"""Snakemake wrapper for Transdecoder Predict"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from os.path import join, basename, dirname, exists
from snakemake.shell import shell
import docker_wrapper

output_dir = str(snakemake.output.dir)
base_dir = dirname(output_dir)
sample_name = basename(base_dir)

extra = snakemake.params["extra"]

log = snakemake.log_fmt_shell(stdout=True, stderr=True)

addl_outputs = ""
pfam = snakemake.params["retain_pfam_hits"]
if pfam:
    addl_outputs += " --retain_pfam_hits " + pfam

blast = snakemake.params["retain_blastp_hits"]
if blast:
    addl_outputs += " --retain_blastp_hits " + blast


# Execution mode setup
docker_prefix, tool_bin = docker_wrapper.docker_wrapper_binary(
    snakemake.config, 
    "transdecoder", 
    "transdecoder_predict_bin", 
    "TransDecoder.Predict"
)

input_fasta = str(snakemake.input.fasta)
if input_fasta.endswith("gz"):
    input_fa = input_fasta.rsplit(".gz")[0]
    shell("gunzip -c {input_fasta} > {input_fa}")
else:
    input_fa = input_fasta

# Ensure .transdecoder_dir exists (from LongOrfs)
created_dir = join(base_dir, f"{basename(input_fa)}.transdecoder_dir")
if not exists(created_dir):
    # Try to restore from snakemake input if available
    td_dir = snakemake.input.td_dir
    if td_dir:
        shell(f"cp -r {td_dir} {created_dir}")

shell(f"{docker_prefix}{tool_bin} -t {input_fa} -O {base_dir} {addl_outputs}{extra}{log}")

# Move outputs to final directory
shell(f"mkdir -p {output_dir}")
for ext in ["bed", "cds", "gff3", "pep"]:
    src = join(base_dir, f"{basename(input_fa)}.transdecoder.{ext}")
    dest = join(output_dir, f"{sample_name}.{ext}")
    if exists(src):
        shell(f"mv {src} {dest}")

created_dir = join(base_dir, f"{basename(input_fa)}.transdecoder_dir")
if exists(created_dir):
    shell("rm -rf {created_dir}")
    