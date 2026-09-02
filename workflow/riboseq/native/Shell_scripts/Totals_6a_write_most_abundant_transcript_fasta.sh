#!/usr/bin/env bash

#read in variables
source common_variables.sh

# Export variables for R script
export RIBO_SEQ_RPF_FILENAMES="$RPF_filenames"
export RIBO_SEQ_TOTALS_FILENAMES="$Totals_filenames"

# Run R script to generate most_abundant_transcripts.txt
# This script requires the R environment (which is part of RNAseq environment)
echo "Running calculate_most_abundant_transcript.R..."
(cd "$PROJECT_ROOT/R_scripts" && Rscript calculate_most_abundant_transcript.R)
if [ $? -ne 0 ]; then
    echo "Error: calculate_most_abundant_transcript.R failed"
    exit 1
fi

#uses the flat text file containing the most abundant transcripts per gene created with calculate_most_abundant_transcript.R to filter the protein coding fasta

python3 $PYTHON_SCRIPTS_DIR/filter_FASTA.py $pc_fasta $most_abundant_transcripts_dir/most_abundant_transcripts.txt $most_abundant_fasta


