#!/bin/bash
# Downstream Step 3: Meta Plots and Feature Analysis

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"
source "$SCRIPT_DIR/run_r_utils.sh"

info "Running Meta Plots and Feature Analysis..."
run_r_step "meta_plots/bin_data.R"
run_r_step "meta_plots/plot_binned_data.R"
run_r_step "meta_plots/normalise_individual_transcript_counts.R"
run_r_step "meta_plots/plot_individual_mRNAs.R"
