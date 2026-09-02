#!/bin/bash
# Downstream Step 2: Differential Expression Analysis (DESeq2)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"
source "$SCRIPT_DIR/run_r_utils.sh"

info "Running DESeq2 Analysis..."
run_r_step "DESeq2/DESeq2_Totals.R"
run_r_step "DESeq2/DESeq2_RPFs.R"
run_r_step "DESeq2/DESeq2_TE.R"
run_r_step "DESeq2/DE_analysis_plots.R"
