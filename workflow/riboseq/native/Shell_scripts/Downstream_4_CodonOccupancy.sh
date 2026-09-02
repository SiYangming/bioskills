#!/bin/bash
# Downstream Step 4: Codon Occupancy

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"
source "$SCRIPT_DIR/run_r_utils.sh"

info "Running Codon Occupancy Analysis..."

# Create output directory
mkdir -p "$codon_counts_dir"

# Run count_codon_occupancy.py to calculate codon occupancy counts
info "Running count_codon_occupancy.py..."

# Activate RiboSeq environment
eval "$(conda shell.bash hook)"
conda activate RiboSeq

for filename in $RPF_filenames
do
    python3 "$PYTHON_SCRIPTS_DIR/count_codon_occupancy.py" "${filename}_pc_final.counts" "$most_abundant_fasta" "$region_lengths" 20 -10 -in_dir "$counts_dir" -out_dir "$codon_counts_dir" &
done
wait

# Deactivate conda environment to avoid interfering with R step
conda deactivate

run_r_step "codon_occupancy.R"
