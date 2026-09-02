#!/bin/bash
# Downstream Step 5: GSEA

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"
source "$SCRIPT_DIR/run_r_utils.sh"

info "Running GSEA..."
run_r_step "gsea/fgsea.R"
