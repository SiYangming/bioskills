#!/usr/bin/env bash

#This script runs fastQC on all your raw fastq files and outputs them in the fastQC directory

#read in variables
source common_variables.sh

#run fastQC
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2.fastq" ]; then
        # Paired-End
        fastqc $fastq_dir/${filename}_1.fastq --outdir=$fastqc_dir &
        fastqc $fastq_dir/${filename}_2.fastq --outdir=$fastqc_dir &
    else
        # Single-End
        fastqc $fastq_dir/${filename}.fastq --outdir=$fastqc_dir &
    fi
done
wait
