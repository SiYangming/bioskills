#Set the parent directory (this should be the same directory as is set in the common_variables.sh script
parent_dir <- Sys.getenv("RIBO_SEQ_PARENT_DIR")
if (parent_dir == "") {
  # Fallback to default if not set
  # Assuming we are in R_scripts directory, go up one level
  parent_dir <- file.path(dirname(getwd()), "results")
  warning("RIBO_SEQ_PARENT_DIR not set. Using default: ", parent_dir)
}

# Genome Version
genome_version <- Sys.getenv("GENOME_VERSION")
if (genome_version == "") {
  genome_version <- "v49"
}

# Fasta Directory
fasta_dir <- Sys.getenv("RIBO_SEQ_FASTA_DIR")
if (fasta_dir == "") {
  # If parent_dir is the results directory, reference should be a sibling
  if (basename(parent_dir) == "results") {
    fasta_dir <- file.path(dirname(parent_dir), "reference")
  } else {
    fasta_dir <- file.path(parent_dir, "reference")
  }
}

#set sample names
# Read sample names from environment variables (space-separated)
RPF_filenames_env <- Sys.getenv("RIBO_SEQ_RPF_FILENAMES")
if (RPF_filenames_env != "") {
  RPF_sample_names <- strsplit(RPF_filenames_env, " ")[[1]]
} else {
  # Fallback to default hardcoded names (or empty)
  RPF_sample_names <- c('Ctrl_RPFs_1', 'Ctrl_RPFs_2', 'Ctrl_RPFs_3', 'Treatment_RPFs_1', 'Treatment_RPFs_2', 'Treatment_RPFs_3')
}

Totals_filenames_env <- Sys.getenv("RIBO_SEQ_TOTALS_FILENAMES")
if (Totals_filenames_env != "") {
  Total_sample_names <- strsplit(Totals_filenames_env, " ")[[1]]
} else {
  # Fallback
  Total_sample_names <- c('Ctrl_Totals_1', 'Ctrl_Totals_2', 'Ctrl_Totals_3', 'Treatment_Totals_1', 'Treatment_Totals_2', 'Treatment_Totals_3')
}

# Try to read info.csv for dynamic condition/replicate info
info_file <- file.path(dirname(parent_dir), "info.csv")
use_default_info <- TRUE

if (file.exists(info_file)) {
  info_data <- read.csv(info_file, stringsAsFactors = FALSE)
  
  # Process RPFs
  rpf_rows <- info_data[info_data$type == 'riboseq', ]
  if (nrow(rpf_rows) == length(RPF_sample_names)) {
    # Calculate replicates: 1,2,3 for control, 1,2,3 for treated
    rpf_rows$replicate <- ave(seq_along(rpf_rows$treatment), rpf_rows$treatment, FUN = seq_along)
    
    RPF_sample_info <- data.frame(sample = RPF_sample_names,
                                  condition = rpf_rows$treatment,
                                  replicate = factor(rpf_rows$replicate))
    use_default_info <- FALSE
  }
  
  # Process Totals
  total_rows <- info_data[info_data$type == 'rnaseq', ]
  if (nrow(total_rows) == length(Total_sample_names)) {
    total_rows$replicate <- ave(seq_along(total_rows$treatment), total_rows$treatment, FUN = seq_along)
    
    Total_sample_info <- data.frame(sample = Total_sample_names,
                                    condition = total_rows$treatment,
                                    replicate = factor(total_rows$replicate))
  }
}

if (use_default_info) {
  # Fallback to hardcoded if info.csv is missing or doesn't match
  RPF_sample_info <- data.frame(sample = RPF_sample_names,
                               condition = c(rep("Ctrl", length(RPF_sample_names)/2), rep("Treatment", length(RPF_sample_names)/2)),
                               replicate = factor(rep(seq(1, length(RPF_sample_names)/2), 2)))
  
  Total_sample_info <- data.frame(sample = Total_sample_names,
                               condition = c(rep("Ctrl", length(Total_sample_names)/2), rep("Treatment", length(Total_sample_names)/2)),
                               replicate = factor(rep(seq(1, length(Total_sample_names)/2), 2)))
}
