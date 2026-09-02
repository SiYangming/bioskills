#load libraries
library(DESeq2)
library(tidyverse)
library(tximport)
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

#read in gene to transcript IDs map and rename and select ENSTM and ENSGM columns----
# Support chr20 subset CSV fallback when the TXT map is unavailable
transcript_info_dir <- file.path(fasta_dir, "GENCODE", genome_version, "transcript_info")
txt_map <- file.path(transcript_info_dir, paste0("gencode.", genome_version, ".pc_transcripts_gene_IDs.txt"))
csv_map_chr20 <- file.path(transcript_info_dir, paste0("gencode.", genome_version, ".pc_transcripts_chr20_gene_IDs.csv"))

if (file.exists(txt_map)) {
  read_tsv(file = txt_map, col_names = FALSE) %>%
    dplyr::rename(GENEID = X1, TXNAME = X2) %>%
    select(TXNAME, GENEID) -> tx2gene
} else if (file.exists(csv_map_chr20)) {
  read_csv(file = csv_map_chr20, col_names = FALSE) %>%
    dplyr::rename(TXNAME = X1, GENEID = X2) %>%
    select(TXNAME, GENEID) -> tx2gene
} else {
  stop(paste0("Transcript-to-gene map not found in ", transcript_info_dir), call. = FALSE)
}

#read in the most abundant transcripts per gene csv file----
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#import rsem data----
#set directory where rsem output is located
rsem_dir <- file.path(parent_dir, 'rsem')

#create a named vector of files (with path)
files <- file.path(rsem_dir, paste0(Total_sample_names, ".isoforms.results"))
names(files) <- Total_sample_names

#import data with txi
txi <- tximport(files, type="rsem", tx2gene=tx2gene)

#create a data frame with the condition/replicate information----
#Filter metadata for RNA-seq samples (Totals)
rna_metadata <- sample_metadata %>% filter(type == "rnaseq")

# Ensure Total_sample_names matches the number of RNA-seq samples
if (length(Total_sample_names) != nrow(rna_metadata)) {
  warning(paste("Number of Total samples defined (", length(Total_sample_names), 
                ") does not match info.csv RNA-seq entries (", nrow(rna_metadata), ")."))
}

# Add replicate numbers (1,2,3 within each condition)
rna_metadata <- rna_metadata %>%
  group_by(treatment) %>%
  mutate(replicate_num = row_number()) %>%
  ungroup()

# Construct sample_info dynamically
sample_info <- data.frame(row.names = Total_sample_names,
                          condition = factor(rna_metadata$treatment, levels = c(control, treatment)),
                          replicate = factor(rna_metadata$replicate_num))

#print the data frame to visually check it has been made as expected
sample_info

#make a DESeq data set from imported data----
ddsTxi <- DESeqDataSetFromTximport(txi,
                                   colData = sample_info,
                                   design = ~ condition + replicate)

#pre-filter to remove genes with less than an average of 10 counts across all samples----
keep <- rowMeans(counts(ddsTxi)) >= 10
table(keep)
ddsTxi <- ddsTxi[keep,]

#make sure levels are set appropriately so that Ctrl is "untreated"
ddsTxi$condition <- relevel(ddsTxi$condition, ref = control)

#run DESeq on DESeq data set----
dds <- DESeq(ddsTxi)

#extract results for each comparison----
res <- results(dds, contrast=c("condition", treatment, control))

#summarise results----
summary(res)

#write summary to a text file
sink(file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_DEseq2_summary.txt")))
summary(res)
sink()

#apply LFC shrinkage for each comparison----
lfc_shrink <- lfcShrink(dds, coef=paste("condition", treatment, "vs", control, sep = "_"), type="apeglm")

#write reslts to csv----
as.data.frame(lfc_shrink[order(lfc_shrink$padj),]) %>%
  rownames_to_column("gene") %>%
  inner_join(most_abundant_transcripts, by = "gene") -> DEseq2_output
write_csv(DEseq2_output, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_DEseq2_apeglm_LFC_shrinkage.csv")))

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
  rownames_to_column("gene") %>%
  inner_join(most_abundant_transcripts, by = "gene") -> normalised_counts
write_csv(normalised_counts, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_normalised_counts.csv")))

#plot PCA----
pcaData <- plotPCA(rld, intgroup=c("condition", "replicate"), returnData=TRUE)
percentVar <- round(100 * attr(pcaData, "percentVar"))

png(filename = file.path(parent_dir, "plots/PCAs", paste0(treatment, "_Totals_PCA.png")), width = 400, height = 350)
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
  ggtitle(paste(treatment, "Totals"))
dev.off()

#apply batch correct and re-plot heatmap and PCA----
mat <- assay(rld)
mat <- limma::removeBatchEffect(mat, rld$replicate)
assay(rld) <- mat

#PCA
pcaData <- plotPCA(rld, intgroup=c("condition", "replicate"), returnData=TRUE)
percentVar <- round(100 * attr(pcaData, "percentVar"))

png(filename = file.path(parent_dir, "plots/PCAs", paste0(treatment, "_Totals_batch_corrected_PCA.png")), width = 400, height = 350)
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
  ggtitle(paste(treatment, "Totals batch corrected"))
dev.off()


