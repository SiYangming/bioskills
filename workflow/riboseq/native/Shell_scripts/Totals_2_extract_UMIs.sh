#!/usr/bin/env bash

#This script uses UMItools to extract the UMIs from the reads and add them to the read name
#The script is written for libraries which contain 12nt UMIs at the 5'end of the read. If this is not the case for your libraries you will need to change the following part of the command
#"--bc-pattern=NNNNNNNNNNNN"
#For more info on UMItools see https://github.com/CGATOxford/UMI-tools and https://umi-tools.readthedocs.io/en/latest/

#It will output a new fastq file with the suffix _UMI_clipped
#It then runs fastQC on output to check it is as expected

#read in variables
source common_variables.sh

#extract UMIs
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2_cutadapt.fastq" ]; then
        # Paired-End UMI extraction
        # Assuming UMI is on Read 1 (5' end) based on SE logic
        echo "Extracting UMIs for $filename (Paired-End)"
        umi_tools extract \
            -I $fastq_dir/${filename}_1_cutadapt.fastq \
            -S $fastq_dir/${filename}_1_UMI_clipped.fastq \
            --read2-in=$fastq_dir/${filename}_2_cutadapt.fastq \
            --read2-out=$fastq_dir/${filename}_2_UMI_clipped.fastq \
            --bc-pattern=NNNNNNNNNNNN \
            --log=$log_dir/${filename}_extracted_UMIs.log &
    else
        # Single-End
        echo "Extracting UMIs for $filename (Single-End)"
        umi_tools extract -I $fastq_dir/${filename}_cutadapt.fastq -S $fastq_dir/${filename}_UMI_clipped.fastq --bc-pattern=NNNNNNNNNNNN --log=$log_dir/${filename}_extracted_UMIs.log &
    fi
done
wait

#run fastqc on output
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2_UMI_clipped.fastq" ]; then
        # Paired-End
        fastqc $fastq_dir/${filename}_1_UMI_clipped.fastq --outdir=$fastqc_dir &
        fastqc $fastq_dir/${filename}_2_UMI_clipped.fastq --outdir=$fastqc_dir &
    else
        # Single-End
        fastqc $fastq_dir/${filename}_UMI_clipped.fastq --outdir=$fastqc_dir &
    fi
done
wait
