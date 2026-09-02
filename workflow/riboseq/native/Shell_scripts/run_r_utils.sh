#!/bin/bash

# Utility functions for R script execution
# Sourced by Downstream pipeline scripts

# Global log functions
if ! command -v info &> /dev/null; then
    info() { echo "[INFO] $@"; }
fi
if ! command -v error &> /dev/null; then
    error() { echo "[ERROR] $@"; }
fi

# Function to run an R step
run_r_step() {
    local script_rel_path="$1"
    local script_name=$(basename "$script_rel_path")
    # Ensure LOG_DIR is defined (if not sourced from run.sh context, try to derive)
    if [ -z "$LOG_DIR" ]; then
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
        LOG_DIR="${PROJECT_ROOT}/logs"
        mkdir -p "$LOG_DIR"
    fi
    
    local log_file="$LOG_DIR/${script_name%.*}.log"

    # Ensure PROJECT_ROOT is defined
    if [ -z "$PROJECT_ROOT" ]; then
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    fi

    info "Starting Step: $script_name"
    
    # We need to run from R_scripts directory so that source("common_variables.R") works
    (
        cd "$PROJECT_ROOT/R_scripts" || exit 1
        # Check if log_file is writable (or if directory is writable)
        if [ ! -w "$(dirname "$log_file")" ]; then
             error "Log directory $(dirname "$log_file") is not writable."
             exit 1
        fi
        
        # Export necessary variables for R script
        export RIBO_SEQ_PARENT_DIR="${PROJECT_ROOT}/results"
        export RIBO_SEQ_RPF_FILENAMES="RPF_1 RPF_2 RPF_3 RPF_4 RPF_5 RPF_6"
        export RIBO_SEQ_TOTALS_FILENAMES="Totals_1 Totals_2 Totals_3 Totals_4 Totals_5 Totals_6"

        # Source samples.env if available to get correct filenames
        if [ -f "${PROJECT_ROOT}/results/samples.env" ]; then
             source "${PROJECT_ROOT}/results/samples.env"
             export RIBO_SEQ_RPF_FILENAMES="$RPF_filenames"
             export RIBO_SEQ_TOTALS_FILENAMES="$Totals_filenames"
        fi

        Rscript "$script_rel_path" > "$log_file" 2>&1
    )
    
    if [ $? -eq 0 ]; then
        info "Step $script_name completed successfully."
    else
        error "Step $script_name failed. Check log: $log_file"
        exit 1
    fi
}
