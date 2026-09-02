#!/usr/bin/env bash

#This script uses UMItools to deduplicate the protein coding <.bam> file

#read in variables
source common_variables.sh

#run UMI tools deduplication function
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2_UMI_clipped.fastq" ]; then
        # Paired-End
        echo "Deduplicating $filename (Paired-End)"
        umi_tools dedup \
            -I $BAM_dir/${filename}_pc_sorted.bam \
            -S $BAM_dir/${filename}_pc_deduplicated.bam \
            --paired \
            --output-stats=$log_dir/${filename}_deduplication \
            1> $log_dir/${filename}_deduplication_log.txt &
    else
        # Single-End
        echo "Deduplicating $filename (Single-End)"
        umi_tools dedup \
            -I $BAM_dir/${filename}_pc_sorted.bam \
            -S $BAM_dir/${filename}_pc_deduplicated.bam \
            --output-stats=$log_dir/${filename}_deduplication \
            1> $log_dir/${filename}_deduplication_log.txt &
    fi
done
wait
