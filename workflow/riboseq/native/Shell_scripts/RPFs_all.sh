#!/usr/bin/env bash

# Master script to run all RPFs steps sequentially
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
run_step "RPFs_0_QC.sh"
run_step "RPFs_1_adaptor_removal.sh"
run_step "RPFs_2_extract_UMIs.sh"
run_step "RPFs_3_align_reads.sh"
run_step "RPFs_4_deduplication.sh"
run_step "RPFs_5_Extract_counts_all_lengths.sh"
run_step "RPFs_6a_summing_region_counts.sh"
run_step "RPFs_6b_summing_spliced_counts.sh"
run_step "RPFs_6c_periodicity.sh"
run_step "RPFs_6d_extract_read_counts.sh"
run_step "RPFs_7_Extract_final_counts.sh"
run_step "RPFs_8a_CDS_counts.sh"
run_step "RPFs_8b_UTR5_counts.sh"
run_step "RPFs_8c_counts_to_csv.sh"
run_step "RPFs_8d_count_codon_occupancy.sh"

echo "All RPFs steps completed successfully."
