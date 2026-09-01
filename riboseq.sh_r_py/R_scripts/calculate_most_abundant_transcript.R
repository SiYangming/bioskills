#load libraries
#加载库。
library(tidyverse)
library(tximport)

#read in common variables
#读取通用变量。
source("common_variables.R")

#read in transcript and gene IDs
#读取转录本和基因 ID。
transcript_to_gene_ID_dir <- "path/to/file" # add the path here
#在此添加文件路径。
transcript_to_gene_ID <- read_csv(file = file.path(transcript_to_gene_ID_dir, "gencode.vM27.pc_transcripts_gene_IDs.csv"), col_names = c("transcript", "gene", "gene_sym"))

#create a vector of rsem isoform file names
#创建 RSEM 同种型结果文件名向量。
rsem_dir <- file.path(parent_dir, 'rsem')
files <- file.path(rsem_dir, paste0(Total_sample_names, ".isoforms.results"))
names(files) <- Total_sample_names

#read in rsem isoform files
#读取 RSEM 同种型结果文件。
isoform_expression <- tximport(files, type = "rsem", txOut = TRUE)

#extract tpms
#提取 TPM 值。
isoform_tpm <- as.data.frame(isoform_expression$abundance)
isoform_tpm %>%
  rownames_to_column("transcript") -> isoform_tpm

#write out tpm values
#导出 TPM 数值。
write_csv(file = file.path(parent_dir, "Analysis/DESeq2_output/tpms.csv"), isoform_tpm)

#calculate mean tpm
#计算每个转录本的平均 TPM。
isoform_tpm %>%
  column_to_rownames("transcript") -> isoform_tpm
isoform_tpm$mean_tpm <- rowMeans(isoform_tpm)

#calculate most abundant transcript across all samples
#计算所有样本中最丰度的转录本。
isoform_tpm %>%
  rownames_to_column("transcript") %>%
  inner_join(transcript_to_gene_ID, by = "transcript") %>%
  group_by(gene) %>%
  top_n(n = 1, wt = mean_tpm) %>%
  sample_n(size = 1) %>% #some genes (particularly those with 0 counts) will have more than one transcript with the joint highest tpm, so we therefore select the transcript by random for these genes
  #对于某些基因（尤其是计数为 0 的基因），可能有多个转录本具有相同的最高 TPM，这里随机选取一个转录本。
  select(transcript, gene, gene_sym) -> most_abundant_transcripts

#check for no duplicates
#检查是否存在重复基因。
nrow(most_abundant_transcripts) == n_distinct(most_abundant_transcripts$gene)

#write out as csv
#将结果写出为 CSV 和文本文件。
write_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"), most_abundant_transcripts)
write.table(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts.txt"), most_abundant_transcripts$transcript, row.names = F, col.names = F, quote = F)

