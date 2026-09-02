#!/usr/bin/env bash

#This script uses STAR to align reads to a genome, which may be neccessary to check for specific knockouts, where specific exons have been removed etc
#It is worth creating a new conda environment just for STAR
#for more info on STAR see https://physiology.med.cornell.edu/faculty/skrabanek/lab/angsd/lecture_notes/STARmanual.pdf

#"--outFilterMultimapNmax" sets maximum number of loci the read is allowed to map to (default is 20, but we set to 5 to be more stringent)
#"--outFilterMismatchNmax" sets the maximum number of mismatches (default is 10, but we set to 5 to be more stringent)
#"--outSAMprimaryFlag AllBestScore" will output all alignments with the best score as primary alignments, rather than default behaviour which will only mark one alignment as primary
#"--alignEndsType EndToEnd" forces end-to-end read alignment, do not soft-clip
#"--outSAMtype BAM Unsorted" outputs an unsorted <.bam> file
#"--outSAMunmapped None" means unmapped reads are not output (set as default)

#samtools then sorts and indexes the <.bam> file

#read in variables
source common_variables.sh

#Align to genome
for filename in $Totals_filenames
do
    if [ -f "$fastq_dir/${filename}_2_UMI_clipped.fastq" ]; then
        # Paired-End
        echo "$STAR_dir"
        echo "$PROJECT_ROOT"
        echo "Aligning $filename to genome (Paired-End)"
        # for mac users, need to use --platform linux/amd64 to avoid error
        # docker run --rm --platform linux/amd64 -v ${PROJECT_ROOT}:${PROJECT_ROOT} -u $(id -u):$(id -g) -w ${PROJECT_ROOT} \
        # community.wave.seqera.io/library/htslib_samtools_star_gawk:ae438e9a604351a4 \
        STAR \
            --runThreadN $threadN \
            --genomeDir $STAR_index \
            --readFilesIn $fastq_dir/${filename}_1_UMI_clipped.fastq $fastq_dir/${filename}_2_UMI_clipped.fastq \
            --outFileNamePrefix $STAR_dir/${filename}_ \
            --outSAMtype BAM Unsorted \
            --outSAMprimaryFlag AllBestScore \
            --outFilterMultimapNmax 5 \
            --outFilterMismatchNmax 5 \
            --alignEndsType EndToEnd \
            --sjdbGTFfile $STAR_GTF
    else
        # Single-End
        echo "Aligning $filename to genome (Single-End)"
        # for mac users, need to use --platform linux/amd64 to avoid error
        # docker run --rm --platform linux/amd64 -v ${PROJECT_ROOT}:${PROJECT_ROOT} -u $(id -u):$(id -g) -w ${PROJECT_ROOT} \
        # community.wave.seqera.io/library/htslib_samtools_star_gawk:ae438e9a604351a4 \
        STAR \
            --readFilesIn $fastq_dir/${filename}_UMI_clipped.fastq \
            --runThreadN $threadN \
            --genomeDir $STAR_index \
            --readFilesCommand cat \
            --outFilterMultimapNmax 5 \
            --outFilterMismatchNmax 5 \
            --outSAMprimaryFlag AllBestScore \
            --alignEndsType EndToEnd \
            --outSAMtype BAM Unsorted \
            --sjdbGTFfile $STAR_GTF \
            --outFileNamePrefix "$STAR_dir/${filename}_"
            
    fi
done

#sort bam
for filename in $Totals_filenames
do
samtools sort $STAR_dir/${filename}_Aligned.out.bam -o $BAM_dir/${filename}_genome_sorted.bam -@ $threadN -m 1G
done

#index bam
for filename in $Totals_filenames
do
samtools index $BAM_dir/${filename}_genome_sorted.bam $BAM_dir/${filename}_genome_sorted.bai &
done
wait
