#!/bin/bash
set -e

# 0. Environment Setup
eval "$(conda shell.bash hook)"
conda activate snakemake

# 1. Execution Configuration
echo "Starting Snakemake workflow..."
echo "Input config: config/config.yaml"
echo "Working directory: $(pwd)"

# Check exec_mode from config
EXEC_MODE=$(grep "exec_mode:" config/config.yaml | head -n 1 | awk -F'"' '{print $2}')
echo "Execution mode: $EXEC_MODE"

# Check output_dir from config
OUTPUT_DIR=$(grep "^output_dir:" config/config.yaml | head -n 1 | awk -F'"' '{print $2}')
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="testdata_results"
fi
echo "Output directory: $OUTPUT_DIR"

SNAKEMAKE_CMD="snakemake"

# Parse arguments
SNAKEMAKE_OPTS=""
if [ "$EXEC_MODE" == "conda" ]; then
    SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS --use-conda"
elif [ "$EXEC_MODE" == "docker" ]; then
    SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS"
elif [ "$EXEC_MODE" == "apptainer" ]; then
    SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS --use-apptainer --apptainer-prefix .snakemake/apptainer/cache --apptainer-args '--bind $PWD:$PWD'"
fi

for arg in "$@"; do
    if [ "$arg" == "--resume" ]; then
        echo "Resume mode enabled: adding --rerun-incomplete"
        SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS --rerun-incomplete"
    else
        SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS $arg"
    fi
done

# 2. Run Snakemake
# -p: print shell commands
# -c 4: use 4 cores
# --latency-wait 60: wait for filesystem latency
$SNAKEMAKE_CMD -s workflow/Snakefile \
    --configfile config/config.yaml \
    -c all \
    -p \
    --latency-wait 60 \
    $SNAKEMAKE_OPTS

# 3. Report Generation
if [[ "$SNAKEMAKE_OPTS" == *"-n"* ]] || [[ "$SNAKEMAKE_OPTS" == *"--dry-run"* ]]; then
    echo "Dry run detected. Skipping report generation."
else
    echo "Generating execution report..."
    mkdir -p $OUTPUT_DIR
    $SNAKEMAKE_CMD -s workflow/Snakefile \
        --configfile config/config.yaml \
        --report $OUTPUT_DIR/report.html \
        -c all \
        $SNAKEMAKE_OPTS
    echo "Analysis complete. Results are in the '$OUTPUT_DIR' directory."
    echo "Report generated: $OUTPUT_DIR/report.html"
fi
