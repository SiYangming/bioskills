#!/usr/bin/env bash

#read in variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../common_variables.sh"

#unzip files
for filename in $RPF_filenames
do
gunzip $fastq_dir/${filename}.fastq.gz &
done
wait
