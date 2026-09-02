#!/usr/bin/env bash

#This script uses UMItools to deduplicate the genome <.bam> file
#It then uses samtools to sort and index the deduplicated <.bam> file (this deduplicated and sorted <.bam> file is what you would load into IGV)

#read in variables
source common_variables.sh

#run UMI tools deduplication function
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2_UMI_clipped.fastq" ]; then
        # Paired-End
        echo "Deduplicating $filename (Paired-End)"
        umi_tools dedup \
            -I $BAM_dir/${filename}_genome_sorted.bam \
            -S $BAM_dir/${filename}_genome_deduplicated.bam \
            --paired \
            --output-stats=$log_dir/${filename}_genome_deduplication \
            1> $log_dir/${filename}_genome_deduplication_log.txt &
    else
        # Single-End
        echo "Deduplicating $filename (Single-End)"
        umi_tools dedup \
            -I $BAM_dir/${filename}_genome_sorted.bam \
            -S $BAM_dir/${filename}_genome_deduplicated.bam \
            --output-stats=$log_dir/${filename}_genome_deduplication \
            1> $log_dir/${filename}_genome_deduplication_log.txt &
    fi
done
wait

#sort bam
for filename in $Totals_filenames
do
samtools sort $BAM_dir/${filename}_genome_deduplicated.bam -o $BAM_dir/${filename}_genome_deduplicated_sorted.bam -@ $threadN -m 1G
done

#index bam
for filename in $Totals_filenames
do
samtools index $BAM_dir/${filename}_genome_deduplicated_sorted.bam $BAM_dir/${filename}_genome_deduplicated_sorted.bai &
done
wait
