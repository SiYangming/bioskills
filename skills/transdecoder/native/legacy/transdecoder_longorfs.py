"""Snakemake wrapper for Transdecoder LongOrfs"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from os.path import join, basename, dirname, exists
from snakemake.shell import shell
import docker_wrapper

output_dir = str(snakemake.output.dir)
base_dir = dirname(output_dir)
    
extra = snakemake.params["extra"]

log = snakemake.log_fmt_shell(stdout=True, stderr=True)

gtm_cmd = ""
gtm = snakemake.params["gene_trans_map"]
if gtm:
    gtm_cmd = f" --gene_trans_map {gtm}"

docker_prefix, tool_bin = docker_wrapper.docker_wrapper_binary(
    snakemake.config, 
    "transdecoder", 
    "transdecoder_longorfs_bin", 
    "TransDecoder.LongOrfs"
)

input_fasta = str(snakemake.input.fasta)
if input_fasta.endswith("gz"):
    input_fa = input_fasta.rsplit(".gz")[0]
    shell("gunzip -c {input_fasta} > {input_fa}")
else:
    input_fa = input_fasta

# Run TransDecoder.LongOrfs
# -O sets the base output directory.
# TransDecoder creates a directory named `basename(input).transdecoder_dir` inside the output directory.
# transdecoder fails if output already exists. No force option available
# We want to keep the directory but clean up previous run's TransDecoder results
created_dir = join(base_dir, f"{basename(input_fa)}.transdecoder_dir")
if exists(created_dir):
    shell("rm -rf {created_dir}")

shell(f"{docker_prefix}{tool_bin} -t {input_fa} -O {base_dir} {gtm_cmd} {extra} {log}")
# shell(f"mkdir -p {output_dir}")
if exists(created_dir):
   shell(f"cp -r {created_dir} {output_dir}")
