"""Snakemake wrapper for TD2 Predict"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from os import getcwd
from os.path import join, basename, dirname, exists
from snakemake.shell import shell
import docker_wrapper

output_dir = str(snakemake.output.dir)
td_dir = str(snakemake.input.td_dir)
sample_name = basename(dirname(td_dir))

extra = snakemake.params["extra"]
log = snakemake.log_fmt_shell(stdout=True, stderr=True)

# Prepare optional inputs
addl_outputs = ""
mmseqs = snakemake.params["retain_mmseqs_hits"]
if mmseqs:
    addl_outputs += f" --retain-mmseqs-hits {mmseqs}"
blast = snakemake.params["retain_blastp_hits"]
if blast:
    addl_outputs += f" --retain_blastp_hits {blast}"
hmmer = snakemake.params["retain_hmmer_hits"]
if hmmer:
    addl_outputs += f" --retain_hmmer_hits {hmmer}"

# TD2.Predict
docker_prefix_td2, tool_bin_td2 = docker_wrapper.docker_wrapper_binary(
    snakemake.config, 
    "td2", 
    "td2_predict_bin", 
    "TD2.Predict"
)

# Prepare output dir
if not exists(output_dir):
    shell(f"mkdir -p {output_dir}")

# Run TD2.Predict
# Command: TD2.Predict -t input.fasta -O output_dir ...
input_fasta = str(snakemake.input.fasta)
if input_fasta.endswith("gz"):
    input_fa = input_fasta.rsplit(".gz")[0]
    shell("gunzip -c {input_fasta} > {input_fa}")
else:
    input_fa = input_fasta
shell(f"{docker_prefix_td2}{tool_bin_td2} -t {input_fa} -O {td_dir} {addl_outputs}{extra}{log}")
shell(f"mkdir -p {output_dir}")

for ext in ["bed", "cds", "gff3", "pep"]:
    src = join(getcwd(), f"{basename(input_fa)}.TD2.{ext}")
    # print(src)
    dest = join(output_dir, f"{sample_name}.{ext}")
    # print(dest)
    if exists(src):
        shell(f"mv {src} {dest}")
