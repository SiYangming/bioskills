#!/bin/bash
set -e

# Expected arguments:
# 1. Recipe path (relative to /build/recipes)
# 2. Output directory (mapped to /build/dist)

RECIPE_PATH="$1"

if [ -z "$RECIPE_PATH" ]; then
    echo "Error: Recipe path not provided."
    exit 1
fi

echo "Building recipe: $RECIPE_PATH"

# Build the package
# We use --output-folder to direct the build artifacts to the mounted dist directory
conda build "$RECIPE_PATH" --output-folder /build/dist -c conda-forge --no-anaconda-upload

echo "Build complete. Artifacts are in /build/dist"

# Optional: Re-index the channel
conda index /build/dist
