#!/bin/bash
set -e

# 1. Environment Configuration
echo "Configuring environment..."

# Source bash_profile as requested
if [ -f ~/.bash_profile ]; then
    source ~/.bash_profile
fi

# Activate conda environment
# Ensuring conda is initialized for this shell session
eval "$(conda shell.bash hook)"

# Check if environment exists
if conda info --envs | grep -q "snakemake"; then
    conda activate snakemake
else
    echo "Warning: 'snakemake' conda environment not found. Attempting to use current environment."
fi

# Check requirements
echo "Checking requirements..."
if ! command -v snakemake &> /dev/null; then
    echo "Error: snakemake command not found."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Warning: docker command not found. Docker execution mode might fail."
fi

# 2. Execution
echo "Starting Snakemake workflow..."
echo "Input config: config/config.yaml"
echo "Working directory: $(pwd)"

# Parse arguments for resume functionality
SNAKEMAKE_OPTS=""

# Check exec_mode from config
EXEC_MODE=$(grep "exec_mode:" config/config.yaml | head -n 1 | awk -F'"' '{print $2}')
echo "Execution mode: $EXEC_MODE"

if [ "$EXEC_MODE" == "conda" ]; then
    SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS --use-conda"
elif [ "$EXEC_MODE" == "docker" ]; then
    SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS"
fi

for arg in "$@"; do
    if [ "$arg" == "--resume" ]; then
        echo "Resume mode enabled: adding --rerun-incomplete"
        SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS --rerun-incomplete"
    else
        SNAKEMAKE_OPTS="$SNAKEMAKE_OPTS $arg"
    fi
done

# Run Snakemake
# -p: print shell commands
# -c 4: use 4 cores
# --latency-wait 60: wait for filesystem latency
snakemake -s workflow/Snakefile \
    --configfile config/config.yaml \
    -c 4 \
    -p \
    --latency-wait 60 \
    $SNAKEMAKE_OPTS

# 3. Report Generation
echo "Generating execution report..."
mkdir -p test_results
snakemake -s workflow/Snakefile \
    --configfile config/config.yaml \
    --report test_results/report.html \
    $SNAKEMAKE_OPTS

echo "Analysis complete. Results are in the 'test_results' directory."
echo "Report generated: test_results/report.html"
