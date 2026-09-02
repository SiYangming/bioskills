#!/bin/bash
# Downstream Step 1: Quality Control

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"
source "$SCRIPT_DIR/run_r_utils.sh"

echo "Running QC Scripts..."
run_r_step "QC/RPFs_read_counts.R"
run_r_step "QC/periodicity.R"
run_r_step "QC/region_counts.R"
run_r_step "QC/heatmaps.R"
run_r_step "QC/offset_plots.R"
run_r_step "QC/offset_aligned_single_nt_plots.R"
