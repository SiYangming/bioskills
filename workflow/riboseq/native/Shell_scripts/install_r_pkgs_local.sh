#!/bin/bash

# Script to install R dependencies for the local environment
# Usage: ./install_r_pkgs_local.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
R_INSTALL_SCRIPT="${PROJECT_ROOT}/R_scripts/install_r_dependencies.R"

echo "Installing R dependencies using local R installation..."
echo "Script: $R_INSTALL_SCRIPT"

if command -v Rscript >/dev/null 2>&1; then
    Rscript "$R_INSTALL_SCRIPT"
else
    echo "Error: Rscript not found. Please ensure R is installed and in your PATH."
    exit 1
fi
