"""Snakemake wrapper for TD2 LongOrfs"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from snakemake.shell import shell
import docker_wrapper

output_dir = str(snakemake.output.dir)
# For TD2, the output dir IS the directory where we want files, unlike TransDecoder which makes a subdir.
# However, to match TransDecoder structure in the workflow, let's see what the rule expects.
# The rule expects a directory. 

extra = snakemake.params["extra"]

log = snakemake.log_fmt_shell(stdout=True, stderr=True)

gtm_cmd = ""
gtm = snakemake.params["gene_trans_map"]
if gtm:
    gtm_cmd = f" --gene_trans_map {gtm}"
# Docker/Binary setup
docker_prefix, tool_bin = docker_wrapper.docker_wrapper_binary(
    snakemake.config, 
    "td2", 
    "td2_longorfs_bin", 
    "TD2.LongOrfs"
)

input_fasta = str(snakemake.input.fasta)
if input_fasta.endswith("gz"):
    # We might need to unzip it to a temp location if TD2 doesn't support gz
    # For now assume we unzip or use process substitution if wrapper handles it.
    # But transdecoder script unzips. Let's do that.
    # Use a temp name or just assume input is unzipped if configured that way?
    # Transdecoder script: shell("gunzip -c {input_fasta} > {input_fa}")
    # We need a place to put it. 
    # Let's use the output_dir parent or tmp.
    # Actually, simpler to just assume input is handled or unzip if needed.
    # Let's stick to simple input for now, or copy transdecoder logic.
    input_fa = input_fasta.rsplit(".gz")[0]
    shell("gunzip -c {input_fasta} > {input_fa}")
else:
    input_fa = input_fasta

# Create output directory if it doesn't exist
shell(f"mkdir -p {output_dir}")

# Run TD2.LongOrfs
# -O specifies the output directory.
shell(f"{docker_prefix}{tool_bin} -t {input_fa} -O {output_dir} {gtm_cmd}{extra}{log}")
