#!/usr/bin/env bash

# Master script to run all Totals steps sequentially
# This ensures consistency with the individual step scripts

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to run a step and check for errors
run_step() {
    local step_script="$1"
    echo "Starting $step_script..."
    
    # Run the script
    bash "$SCRIPT_DIR/$step_script"
    
    # Check exit status
    if [ $? -ne 0 ]; then
        echo "Error: $step_script failed."
        exit 1
    fi
    echo "Finished $step_script"
}

# Run all steps in order
run_step "Totals_0_QC.sh"
run_step "Totals_1_adaptor_removal.sh"
run_step "Totals_2_extract_UMIs.sh"
run_step "Totals_3a_align_reads_transcriptome.sh"
run_step "Totals_3b_align_reads_genome.sh"
run_step "Totals_4a_deduplication_transcriptome.sh"
run_step "Totals_4b_deduplication_genome.sh"
run_step "Totals_5_isoform_quantification.sh"
run_step "Totals_6a_write_most_abundant_transcript_fasta.sh"
run_step "Totals_6b_extract_read_counts.sh"

echo "All Totals steps completed successfully."
