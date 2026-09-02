#!/usr/bin/env bash

#read in variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../common_variables.sh"

#concatenate seperate fastq files into one
cat ${fastq_dir}/RPFs_1a.fastq ${fastq_dir}/RPFs_1b.fastq > ${fastq_dir}/RPFs_1.fastq
cat ${fastq_dir}/RPFs_2a.fastq ${fastq_dir}/RPFs_2b.fastq > ${fastq_dir}/RPFs_2.fastq


