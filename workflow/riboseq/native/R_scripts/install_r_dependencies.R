#!/usr/bin/env Rscript

# R script to install project dependencies
# This script is optimized for local R environments.

# 1. Setup CRAN mirror (using cloud mirror for reliability, or Tsinghua if preferred)
# Using cloud mirror to avoid potential sync issues, or fallback to 
options(repos = c(CRAN = "https://cloud.r-project.org"))

# 2. Install BiocManager if not present
if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

# 3. Configure Bioconductor Mirror (optional, comment out if using main)
# options(BioC_mirror = "https://mirrors.tuna.tsinghua.edu.cn/bioconductor")

# 4. List of required packages
cran_pkgs <- c(
  "tidyverse",    # includes ggplot2, dplyr, stringr, etc.
  "data.table",
  "gridExtra",
  "viridis",
  "ggrepel",
  "igraph",
  "pROC",
  "fst",
  "pdp", 
  "lime"
)

bioc_pkgs <- c(
  "DESeq2",
  "tximport",
  "apeglm",
  "fgsea",
  "rrvgo",
  "Glimma",
  "vsn"
)

# 5. Install CRAN packages
message("Installing CRAN packages...")
for (pkg in cran_pkgs) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    message(paste("Installing", pkg))
    install.packages(pkg)
  } else {
    message(paste(pkg, "already installed"))
  }
}

# 6. Install Bioconductor packages
message("Installing Bioconductor packages...")
BiocManager::install(bioc_pkgs, update = FALSE, ask = FALSE)

message("Package installation check completed.")
