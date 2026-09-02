#!/bin/bash

# Downstream Analysis Pipeline Script
# Executes all Downstream steps in order

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"

# Helper to run shell script step
run_shell_step() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    info "Executing $script_name..."
    "$script_path"
    if [ $? -ne 0 ]; then
        error "$script_name failed."
        exit 1
    fi
}

info "Starting Downstream Analysis Pipeline..."

run_shell_step "Downstream_1_QC.sh"
run_shell_step "Downstream_2_DESeq2.sh"
run_shell_step "Downstream_3_MetaPlots.sh"
run_shell_step "Downstream_4_CodonOccupancy.sh"
run_shell_step "Downstream_5_GSEA.sh"

info "Downstream Analysis Pipeline Completed Successfully."
