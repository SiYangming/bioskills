#!/usr/bin/env bash

#read in variables
source common_variables.sh

#make directories
mkdir -p $fastq_dir
mkdir -p $fastqc_dir
mkdir -p $SAM_dir
mkdir -p $BAM_dir
mkdir -p $log_dir
mkdir -p $counts_dir
mkdir -p $rsem_dir
mkdir -p $STAR_dir

mkdir -p $analysis_dir
mkdir -p $region_counts_dir
mkdir -p $spliced_counts_dir
mkdir -p $periodicity_dir
mkdir -p $cds_counts_dir
mkdir -p $UTR5_counts_dir
mkdir -p $csv_counts_dir
mkdir -p $csv_R_objects
mkdir -p $codon_counts_dir
mkdir -p $DESeq2_dir
mkdir -p $most_abundant_transcripts_dir
mkdir -p $reads_summary_dir
mkdir -p $fgsea_dir

mkdir -p $plots_dir
mkdir -p $summed_counts_plots_dir
mkdir -p $periodicity_plots_dir
mkdir -p $offset_plots_dir
mkdir -p $heatmaps_plots_dir
mkdir -p $DE_analysis_dir
mkdir -p $PCA_dir
mkdir -p $Interactive_scatters_dir
mkdir -p $fgsea_plots_dir
mkdir -p $fgsea_scatters_dir
mkdir -p $fgsea_interactive_scatters_dir
mkdir -p $read_counts_summary_dir
mkdir -p $binned_plots_dir
mkdir -p $single_transcript_binned_plots_dir
mkdir -p $normalisation_binned_plots_dir


