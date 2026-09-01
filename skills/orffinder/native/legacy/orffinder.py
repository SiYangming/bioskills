"""Snakemake wrapper for ORFfinder"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from os.path import dirname, exists
from snakemake.shell import shell
import docker_wrapper

outfmt = int(snakemake.params["outfmt"])
extra = snakemake.params["extra"]
log = snakemake.log_fmt_shell(stdout=True, stderr=True)

# Resolve binary and optional container wrapper
docker_prefix, tool_bin = docker_wrapper.docker_wrapper_binary(
    snakemake.config,
    "orffinder",
    "orffinder_bin",
    "ORFfinder",
)

input_fasta = str(snakemake.input.fasta)
output_file = str(snakemake.output.file)

# Ensure output directory exists
out_dir = dirname(output_file)
if not exists(out_dir):
    shell(f"mkdir -p {out_dir}")

# Decompress gz if needed
if input_fasta.endswith(".gz"):
    input_fa = input_fasta.rsplit(".gz")[0]
    shell("gunzip -c {input_fasta} > {input_fa}")
else:
    input_fa = input_fasta

# Run ORFfinder
shell(f"{docker_prefix}{tool_bin} -in {input_fa} -out {output_file} -outfmt {outfmt} {extra} -logfile {log}")
