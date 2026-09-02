#load packages----
library(tidyverse)

#read in common variables----
source("common_variables.R")

#read in functions----
source("meta_plots/binning_RiboSeq_functions.R")

#read in data----
region_lengths_file <- file.path(fasta_dir, "GENCODE", genome_version, "transcript_info", paste0("gencode.", genome_version, ".pc_transcripts_region_lengths.csv"))
if (!file.exists(region_lengths_file)) {
  # Try chr20 version for testing environment
  region_lengths_file_chr20 <- file.path(fasta_dir, "GENCODE", genome_version, "transcript_info", paste0("gencode.", genome_version, ".pc_transcripts_chr20_region_lengths.csv"))
  if (file.exists(region_lengths_file_chr20)) {
    region_lengths_file <- region_lengths_file_chr20
    message("Using chr20 region lengths file: ", region_lengths_file)
  }
}
region_lengths <- read_csv(file = region_lengths_file, col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))

#read in tpms----
#this reads in the tpms for each transcript and gathers them in tidy format
#It then inner joins the sample info data frame (from common variables) to obtain condition and replicate info
read_csv(file = file.path(parent_dir, "Analysis/DESeq2_output/tpms.csv")) %>%
  select(transcript, Total_sample_names) %>%
  gather(key = sample, value = tpm, all_of(Total_sample_names)) %>%
  inner_join(Total_sample_info, by = "sample") -> tpms

#read in counts data----
counts_list <- list()
for (sample in RPF_sample_names) {
  
  #extract the condition and replicate from the sample name (this may need to be edited depending on how your sample names are structured)
  condition <- RPF_sample_info$condition[RPF_sample_info$sample == sample]
  replicate <- RPF_sample_info$replicate[RPF_sample_info$sample == sample]
  
  #get all the csv file names from the directory and filter
  read_csv(file = file.path(parent_dir, "Counts_files/csv_files", paste0(sample, "_pc_final_counts.csv"))) %>%
    mutate(condition = rep(condition),
           replicate = rep(replicate)) %>%
    normalise_data(tpms = tpms) -> counts_list[[sample]]
}

#save list----
save(file = file.path(parent_dir, "Counts_files/R_objects/counts_list.Rdata"), counts_list)
