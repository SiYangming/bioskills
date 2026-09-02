#!/usr/bin/env bash

#This script uses RSEM to calculate isoform and gene level expression from deduplicated BAM file.
#--strandedness describes the strand of the genome that the sequencing reads should align to. For the CORALL kit this is forward, but for a lot of standed Illumina Tru-seq kits this will be reverse. If this is not known then it is best to try both and the alignment logs should tell you which is correct
#--fragment-length-mean 300 --fragment-length-sd 100 sets the mean and standard deviation of the library fragment size. These do not need to be exact but best estimates. These are good starting values to use for the CORALL kit

#read in variables
source common_variables.sh

#Run RSEM to quantify gene and isoform level expression
for filename in $Totals_filenames
do
    # Check for paired-end data
    if [ -f "$fastq_dir/${filename}_2_UMI_clipped.fastq" ] || [ -f "$fastq_dir/${filename}_2.fastq" ] || [ -f "$fastq_dir/${filename}_2.fastq.gz" ]; then
        # Paired-end
        echo "Processing $filename (Paired-End)..."
        (
            # Filter for proper pairs and sort by name for RSEM
             samtools view -f 2 -b $BAM_dir/${filename}_pc_deduplicated.bam | samtools sort -n -o $BAM_dir/${filename}_pc_deduplicated_name_sorted.bam -
            
            # Run RSEM
            rsem-calculate-expression --paired-end --strandedness forward --fragment-length-mean 300 --fragment-length-sd 100 --alignments $BAM_dir/${filename}_pc_deduplicated_name_sorted.bam $rsem_index $rsem_dir/${filename}
            
            # Clean up sorted BAM
            rm $BAM_dir/${filename}_pc_deduplicated_name_sorted.bam
        ) &
    else
        # Single-end
        rsem-calculate-expression --strandedness forward --fragment-length-mean 300 --fragment-length-sd 100 --alignments $BAM_dir/${filename}_pc_deduplicated.bam $rsem_index $rsem_dir/${filename} &
    fi
done
wait
