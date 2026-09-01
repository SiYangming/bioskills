"""Snakemake wrapper for ORFanage"""

__author__ = "Yangming Si"
__copyright__ = "Copyright 2026, Yangming Si"
__email__ = "siyangming1991@163.com"
__license__ = "MIT"

from os.path import join, exists
import glob
from snakemake.shell import shell

# Inputs
query_dir = snakemake.input.query_dir
# Find the .gff3 file in query_dir. Expecting *.transdecoder.gff3
gff_files = glob.glob(join(query_dir, "*.transdecoder.gff3"))
if not gff_files:
    # Fallback or error. Maybe just *.gff3
    gff_files = glob.glob(join(query_dir, "*.gff3"))
    if not gff_files:
        raise ValueError(f"No GFF3 file found in {query_dir}")
query = gff_files[0]

templates = snakemake.input.templates
reference = snakemake.input.reference

# Output
output_dir = str(snakemake.output.dir)
# Ensure output dir exists
shell(f"mkdir -p {output_dir}")
# Determine output filename
output_file = join(output_dir, "orfanage.gtf")

# Params
p = snakemake.params

args = []

# Boolean flags
if p["cleanq"]: args.append("--cleanq")
if p["cleant"]: args.append("--cleant")
if p["rescue"]: args.append("--rescue")
if p["use_id"]: args.append("--use-id")
if p["non_aug"]: args.append("--non-aug")
if p["keep_all_cds"]: args.append("--keep-all-cds")
if p["keep_cds_if_not_found"]: args.append("--keep-cds-if-not-found")
if p["spliced_overhang"]: args.append("--spliced-overhang")

# Value args
if p["lpi"] != -1: args.append(f"--lpi {p['lpi']}")
if p["ilpi"] != -1: args.append(f"--ilpi {p['ilpi']}")
if p["mlpi"] != -1: args.append(f"--mlpi {p['mlpi']}")
if p["minlen"] > 0: args.append(f"--minlen {p['minlen']}")
if p["mode"]: args.append(f"--mode {p['mode']}")
if p["stats"]: args.append(f"--stats {p['stats']}")
if p["overhang"] > 0: args.append(f"--overhang {p['overhang']}")

# Threads
threads = p["threads"]
args.append(f"--threads {threads}")

# Extra
if p["extra"]: args.append(p["extra"])

# Reference (required for some flags, but good to pass if present)
if reference:
    # Check if reference is a list or string
    ref = reference[0] if isinstance(reference, list) else reference
    args.append(f"--reference {ref}")

# Templates (positional args)
# templates is a list
tpls = " ".join(templates) if isinstance(templates, list) else str(templates)

args_str = " ".join(args)

cmd = f"orfanage --query {query} --output {output_file} {args_str} {tpls}"

log = snakemake.log_fmt_shell(stdout=True, stderr=True)
shell(f"{cmd} {log}")
