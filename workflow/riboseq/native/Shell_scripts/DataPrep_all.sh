#!/bin/bash

# Data Preparation Sub-process
# This script serves as a guide and entry point for the Data Preparation phase (Phase 0).
# It helps you prepare raw data (SRA, BCL) into the FASTQ format required by the main pipeline.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/common_variables.sh"

echo "========================================================"
echo "   Data Preparation Sub-process (Phase 0)"
echo "========================================================"
echo ""
echo "The scripts for this phase are located in: $SCRIPT_DIR/Data_Preparation/"
echo ""
echo "Available templates and tools:"
echo "1. DataPrep_1_Download.sh     : Template for downloading SRA data."
echo "2. DataPrep_1_Demultiplex.sh  : Template for converting BCL to FASTQ."
echo "3. DataPrep_2_Concatenate.sh  : Template for merging FASTQ files."
echo "4. DataPrep_3_Rename.sh       : Template for renaming files."
echo "5. DataPrep_4_Unzip.sh        : Utility to unzip all FASTQ files listed in variables."
echo ""
echo "NOTE: Steps 1-3 are mutually exclusive or specific to your data source."
echo "      You should edit these scripts manually to match your specific filenames/accessions."
echo ""

# Check if user wants to run Unzip
echo "Do you want to run the Unzip utility (DataPrep_4_Unzip.sh) now?"
echo "This will unzip files for: $RPF_filenames $Totals_filenames"
read -p "Run unzip? [y/N]: " run_unzip

if [[ "$run_unzip" =~ ^[Yy]$ ]]; then
    echo "Running DataPrep_4_Unzip.sh..."
    bash "$SCRIPT_DIR/Data_Preparation/DataPrep_4_Unzip.sh"
    echo "Unzip completed."
else
    echo "Skipping unzip."
fi

echo ""
echo "Data Preparation phase completed. You can now proceed to RPFs_all.sh or Totals_all.sh."
