#load libraries
library(DESeq2)
library(tidyverse)
library(vsn)

#read in common variables
source("common_variables.R")

#create a variable for what the treatment is----
# Dynamically read grouping info from info.csv
info_file <- file.path(dirname(parent_dir), "info.csv")
if (!file.exists(info_file)) info_file <- file.path(parent_dir, "info.csv")

if (!file.exists(info_file)) {
  stop(paste("info.csv not found at", info_file))
}

sample_metadata <- read_csv(info_file, show_col_types = FALSE)

# Extract unique treatment levels
treatments <- unique(sample_metadata$treatment)
if ("control" %in% treatments) {
  control <- "control"
  treatment <- setdiff(treatments, "control")[1]
} else {
  control <- treatments[1]
  treatment <- treatments[2]
}

#read in the most abundant transcripts per gene csv file----
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#read in data----
#the following for loop reads in each final CDS counts file and renames the counts column by the sample name and saves each data frame to a list
data_list <- list()
for (sample in RPF_sample_names) {
  df <- read_csv(file = file.path(parent_dir, "Analysis/CDS_counts", paste0(sample, "_pc_final_counts_all_frames.csv")), col_names = T)
  colnames(df) <- c("transcript", sample)
  data_list[[sample]] <- df
}

#merge all data within the above list using reduce
#Using full join retains all transcripts, but the NAs need to be replaced with 0 as these are transcipts that had 0 counts in that sample
#DESeq2 needs the transcripts to be as rownames, not as a column
data_list %>%
  reduce(full_join, by = "transcript") %>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  column_to_rownames("transcript") -> RPF_counts

#create a data frame with the condition/replicate information----
#Filter metadata for RPF samples
ribo_metadata <- sample_metadata %>% filter(type == "riboseq")

# Ensure RPF_sample_names matches the number of RPF samples
if (length(RPF_sample_names) != nrow(ribo_metadata)) {
  warning(paste("Number of RPF samples defined (", length(RPF_sample_names), 
                ") does not match info.csv RPF entries (", nrow(ribo_metadata), ")."))
}

# Add replicate numbers (1,2,3 within each condition)
ribo_metadata <- ribo_metadata %>%
  group_by(treatment) %>%
  mutate(replicate_num = row_number()) %>%
  ungroup()

# Construct sample_info dynamically
sample_info <- data.frame(row.names = RPF_sample_names,
                          condition = factor(ribo_metadata$treatment, levels = c(control, treatment)),
                          replicate = factor(ribo_metadata$replicate_num))

#print the data frame to visually check it has been made as expected
sample_info

#make a DESeq data set from imported data----
DESeq2data <- DESeqDataSetFromMatrix(countData = RPF_counts,
                                     colData = sample_info,
                                     design = ~ replicate + condition)

#pre-filter to remove genes with low counts----
# Relaxed filter for small datasets/testing: keep genes with at least 1 count total
keep <- rowSums(counts(DESeq2data)) > 0
table(keep)
DESeq2data <- DESeq2data[keep,]

#make sure levels are set appropriately so that Ctrl is "untreated"
DESeq2data$condition <- relevel(DESeq2data$condition, ref = control)

#run DESeq on DESeq data set----
# Use poscounts to handle genes with some zeros (common in sparse/small data)
dds <- estimateSizeFactors(DESeq2data, type="poscounts")
dds <- DESeq(dds)

#extract results for each comparison----
res <- results(dds, contrast=c("condition", treatment, control))

#summarise results----
summary(res)

#write summary to a text file
sink(file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_DEseq2_summary.txt")))
summary(res)
sink()

#apply LFC shrinkage for each comparison----
lfc_shrink <- lfcShrink(dds, coef=paste("condition", treatment, "vs", control, sep = "_"), type="apeglm")

#write reslts to csv----
as.data.frame(lfc_shrink[order(lfc_shrink$padj),]) %>%
  rownames_to_column("transcript") %>%
  inner_join(most_abundant_transcripts, by = "transcript") -> DEseq2_output
write_csv(DEseq2_output, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_DEseq2_apeglm_LFC_shrinkage.csv")))

#extract normalised counts and plot SD vs mean----
ntd <- normTransform(dds) #this gives log2(n + 1)
# Use varianceStabilizingTransformation directly for small datasets (<1000 rows)
vsd <- varianceStabilizingTransformation(dds, blind=FALSE) 
rld <- rlog(dds, blind=FALSE) #Regularized log transformation

meanSdPlot(assay(ntd))
meanSdPlot(assay(vsd))
meanSdPlot(assay(rld))

#write out normalised counts data----
#Regularized log transformation looks preferable for this data. Check for your own data and select the appropriate one
#The aim is for the range of standard deviations to be similar across the range of abundances, i.e. for the red line to be flat
as.data.frame(assay(rld)) %>%
  rownames_to_column("transcript") %>%
  inner_join(most_abundant_transcripts, by = "transcript") -> normalised_counts
write_csv(normalised_counts, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_normalised_counts.csv")))

#plot PCA----
pcaData <- plotPCA(rld, intgroup=c("condition", "replicate"), returnData=TRUE)
percentVar <- round(100 * attr(pcaData, "percentVar"))

png(filename = file.path(parent_dir, "plots/PCAs", paste0(treatment, "_RPFs_PCA.png")), width = 400, height = 350)
ggplot(pcaData, aes(PC1, PC2, color=condition, shape=replicate)) +
  geom_point(size=3) +
  geom_text(aes(label=replicate), colour = 'black',size = 6, nudge_x = 2, vjust=1)+
  xlab(paste0("PC1: ",percentVar[1],"% variance")) +
  ylab(paste0("PC2: ",percentVar[2],"% variance")) + 
  theme_bw()+
  theme(axis.title = element_text(size = 18),
        axis.text = element_text(size = 16),
        legend.text = element_text(size = 18),
        legend.title = element_blank(),
        plot.title = element_text(size = 20, face = "bold", hjust = 0.5))+
  ggtitle(paste(treatment, "RPFs"))
dev.off()

#apply batch correct and re-plot heatmap and PCA----
mat <- assay(rld)
mat <- limma::removeBatchEffect(mat, rld$replicate)
assay(rld) <- mat

#PCA
pcaData <- plotPCA(rld, intgroup=c("condition", "replicate"), returnData=TRUE)
percentVar <- round(100 * attr(pcaData, "percentVar"))

png(filename = file.path(parent_dir, "plots/PCAs", paste0(treatment, "_RPFs_batch_corrected_PCA.png")), width = 400, height = 350)
ggplot(pcaData, aes(PC1, PC2, color=condition, shape=replicate)) +
  geom_point(size=3) +
  geom_text(aes(label=replicate), colour = 'black',size = 6, nudge_x = 2, vjust=1)+
  xlab(paste0("PC1: ",percentVar[1],"% variance")) +
  ylab(paste0("PC2: ",percentVar[2],"% variance")) + 
  theme_bw()+
  theme(axis.title = element_text(size = 18),
        axis.text = element_text(size = 16),
        legend.text = element_text(size = 18),
        legend.title = element_blank(),
        plot.title = element_text(size = 20, face = "bold", hjust = 0.5))+
  ggtitle(paste(treatment, "RPFs batch corrected"))
dev.off()


