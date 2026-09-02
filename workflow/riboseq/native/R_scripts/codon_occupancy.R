#This script will need some editing for sample names and still needs annotating properly

library(tidyverse)
library(grid)
library(gridExtra)

# Source common variables
if (file.exists("common_variables.R")) {
  source("common_variables.R")
} else if (file.exists("R_scripts/common_variables.R")) {
  source("R_scripts/common_variables.R")
} else {
  stop("Could not find common_variables.R")
}

myTheme <- theme_bw()+
  theme(plot.title = element_text(size = 20, face = "bold", hjust = 0.5),
        axis.title = element_text(size = 18),
        axis.text = element_text(size = 16),
        legend.title = element_text(size = 18),
        legend.text = element_text(size = 16))

#read in data----
data_list <- list()
for (sample in RPF_sample_names) {
  # Updated filename pattern to match python output
  # python output: filename_pc_final_codon_counts_20_-10.csv
  input_file <- file.path(parent_dir, "Analysis/codon_counts", paste0(sample, "_pc_final_codon_counts_20_-10.csv"))
  
  if (!file.exists(input_file)) {
      warning("File not found: ", input_file)
      next
  }
  
  df <- read_csv(file = input_file, show_col_types = FALSE)
  
  #filter out stop codons and normalise data
  df %>%
    filter(codon != "TGA" & codon != "TAG" & codon != "TAA") %>%
    mutate(minus_4 = (log2(`-4`)) - log2(total / 7),
           minus_3 = (log2(`-3`)) - log2(total / 7),
           E_site = (log2(E)) - log2(total / 7),
           P_site = (log2(P)) - log2(total / 7),
           A_site = (log2(A)) - log2(total / 7),
           plus_1 = (log2(`1`)) - log2(total / 7),
           plus_2 = (log2(`2`)) - log2(total / 7)) %>%
    select(codon, minus_4, minus_3, E_site, P_site, A_site, plus_1, plus_2) %>%
    mutate(sample = factor(rep(sample))) -> data_list[[sample]]
}

if (length(data_list) == 0) {
    stop("No data loaded. Check input files.")
}

data <- do.call("rbind", data_list)

#gather the data into tidy format----
data %>%
  pull(codon) %>%
  unique() -> codons

gathered_list <- list()
for (sample in names(data_list)) { # Use names(data_list) to avoid empty entries
  for (codon in codons) {
    data[data$codon == codon & data$sample == sample,] %>%
      select(-sample) %>%
      gather(key = codon, value = freq) %>%
      rename(position = codon) %>%
      mutate(codon = rep(codon),
             sample = factor(rep(sample))) -> gathered_list[[paste(codon, sample, sep = "_")]]
  }
}
gathered_data <- do.call("rbind", gathered_list)

gathered_data %>%
  mutate(position = as.numeric(case_when(position == "minus_4" ~ -4,
                                         position == "minus_3" ~ -3,
                                         position == "E_site" ~ -2,
                                         position == "P_site" ~ -1,
                                         position == "A_site" ~ 0,
                                         position == "plus_1" ~ 1,
                                         position == "plus_2" ~ 2)),
         wobble = factor(str_sub(codon, 3,3))) -> plot_data

#plot normalised data----
# Ensure output directory exists
dir.create(file.path(parent_dir, "plots/codon_occupancy"), recursive = TRUE, showWarnings = FALSE)

for (sample in names(data_list)) {
  plot_title <- str_replace_all(sample, "_", " ")
  plot_title <- str_remove(plot_title, " RPFs")
  
  plot_data[plot_data$sample == sample,] %>%
    ggplot(aes(x = position, y = freq, colour = wobble))+
    geom_point(size = 2)+
    stat_summary(fun=mean, geom="line", size = 1)+
    ylab("normalised codon frequency")+
    scale_x_continuous(limits = c(-4,2), breaks = -4:2)+
    xlab("Codon position (0 = A-site)")+
    ggtitle(plot_title)+
    myTheme -> codon_plot
  
  png(filename = file.path(parent_dir, "plots/codon_occupancy/", paste0(sample, "_normalised_codon_freq.png")), width = 500, height = 300)
  print(codon_plot)
  dev.off()
}

#calculate delta between samples----
# Use RPF_sample_info to determine conditions
# Assuming 2 conditions, control and treatment.

if (exists("RPF_sample_info")) {
    conditions <- unique(RPF_sample_info$condition)
    if (length(conditions) >= 2) {
        control <- conditions[1]
        treatment <- conditions[2]
        
        # Check if we can identify control specifically
        ctrl_idx <- grep("control|ctrl|wt", conditions, ignore.case = TRUE)
        if (length(ctrl_idx) > 0) {
            control <- conditions[ctrl_idx[1]]
            treatment <- conditions[conditions != control][1]
        }
        
        # Create mapping
        sample_to_condition <- RPF_sample_info$condition
        names(sample_to_condition) <- RPF_sample_info$sample
        
        plot_data_grouped <- plot_data %>%
          mutate(group = sample_to_condition[as.character(sample)]) %>%
          filter(!is.na(group))
          
        delta_data <- plot_data_grouped %>%
          group_by(group, codon, position) %>%
          summarise(mean_freq = mean(freq)) %>%
          ungroup() %>%
          spread(key = group, value = mean_freq) 
          
        # Check if control and treatment columns exist
        if (control %in% colnames(delta_data) && treatment %in% colnames(delta_data)) {
            delta_data <- delta_data %>%
              mutate(delta_freq = .data[[treatment]] - .data[[control]],
                     wobble = factor(str_sub(codon, 3,3)))
            
            #plot delta----
            delta_data %>%
              ggplot(aes(x = position, y = delta_freq, colour = wobble))+
              geom_point() +
              stat_summary(fun=mean, geom="line")+
              scale_x_continuous(limits = c(-4,2), breaks = -4:2)+
              xlab("Codon position (0 = A-site)")+
              ylab(paste0("log2FC codon enrichment\n(", treatment, " / ", control, ")"))+
              myTheme -> delta_plot

            png(filename = file.path(parent_dir, "plots/codon_occupancy/codon_enrichment_delta.png"), width = 500, height = 500)
            print(delta_plot)
            dev.off()

            #plot scatter plots for A and P-sites----
            delta_data %>%
              filter(position == 0) %>%
              ggplot(aes(x = .data[[control]], y = .data[[treatment]], colour = wobble))+
              geom_point()+
              geom_abline(lty=2)+
              ggtitle("A-site enrichment")+
              myTheme -> A_site_scatter_plot

            delta_data %>%
              filter(position == -1) %>%
              ggplot(aes(x = .data[[control]], y = .data[[treatment]], colour = wobble))+
              geom_point()+
              geom_abline(lty=2)+
              ggtitle("P-site enrichment")+
              myTheme -> P_site_scatter_plot

            png(filename = file.path(parent_dir, "plots/codon_occupancy/A_and_P_site_scatter_plots.png"), width = 800, height = 300)
            grid.arrange(A_site_scatter_plot, P_site_scatter_plot, nrow = 1)
            dev.off()
        } else {
             message("Could not find control/treatment columns for delta calculation.")
        }
    } else {
        message("Not enough conditions for delta calculation.")
    }
} else {
    message("RPF_sample_info not found, skipping delta calculation.")
}
