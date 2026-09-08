#!/bin/bash
set -e

# ==============================================================================
# General Conda Build Script
# 归档说明（2026-09）：用于 modules/<sw>/native/conda-recipe/<platform> 的本地 conda 构建，
# 产物输出 ./dist（已被 .gitignore 忽略，不随仓库入库）；Linux/amd64 容器化构建见
# scripts/docker-conda-builder/。
# Usage: ./build_conda.sh [RECIPE_PATH] [EXTRA_ARGS...]
# Example: ./build_conda.sh ./riboss --no-test
# ==============================================================================

# 1. Initialize Conda for script usage
# Try to source conda.sh to ensure 'conda' function is available
if [ -n "$CONDA_EXE" ] && [ -f "${CONDA_EXE%/*}/../etc/profile.d/conda.sh" ]; then
    source "${CONDA_EXE%/*}/../etc/profile.d/conda.sh"
elif [ -f "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh" ]; then
    source "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh"
else
    # Fallback: assume conda is in PATH and initialized
    eval "$(conda shell.bash hook)"
fi

# 2. Check and Activate Environment
ENV_NAME="conda_build"
echo ">> Activating environment: $ENV_NAME"

if ! conda activate "$ENV_NAME" 2>/dev/null; then
    echo "Error: Environment '$ENV_NAME' not found or could not be activated."
    echo "Please create it first using one of the following commands:"
    echo "  # For Linux-64:"
    echo "  conda create -n $ENV_NAME conda-build anaconda-client conda-verify"
    echo "  # For macOS-ARM64:"
    echo "  conda create -n $ENV_NAME conda-build anaconda-client conda-forge::conda-verify==3.1.1"
    exit 1
fi

# 3. Configure Environment Variables
echo ">> Setting CONDA_SOLVER=libmamba"
export CONDA_SOLVER=libmamba

# 4. Parse Arguments
RECIPE_PATH="${1:-.}"
shift || true
EXTRA_BUILD_ARGS="$@"

# 5. Platform Specific Pre-checks (Linux-64)
PLATFORM=$(uname)
ARCH=$(uname -m)

if [[ "$PLATFORM" == "Linux" && "$ARCH" == "x86_64" ]]; then
    echo ">> Detected Linux-64. Checking for bioconda-utils..."
    if command -v bioconda-utils &> /dev/null; then
        echo ">> Running bioconda-utils lint..."
        bioconda-utils lint "$RECIPE_PATH" --loglevel=debug || echo "Warning: Linting failed, but proceeding with build..."
    else
        echo ">> bioconda-utils not found. Skipping linting."
    fi
fi

# 6. Execute Build
# Default channels and output folder as per instructions
CHANNELS="-c conda-forge -c bioconda"
OUTPUT_FOLDER="dist"

echo ">> Building package from: $RECIPE_PATH"
echo ">> Output folder: $OUTPUT_FOLDER"
echo ">> Channels: $CHANNELS"
echo ">> Extra Args: $EXTRA_BUILD_ARGS"

# Construct command
CMD="conda build \"$RECIPE_PATH\" $CHANNELS --output-folder \"$OUTPUT_FOLDER\" $EXTRA_BUILD_ARGS"

echo ">> Executing: $CMD"
eval "$CMD"

echo ">> Build completed."
