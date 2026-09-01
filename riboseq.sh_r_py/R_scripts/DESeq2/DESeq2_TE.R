#load libraries
#加载库。
library(tidyverse)

#read in common variables
#读取通用变量。
source("common_variables.R")

#create a variable for what the treatment is----
#创建处理组和对照组变量。
treatment <- "KO"
control <- "WT"

#read in the most abundant transcripts per gene csv file----
#读取每个基因最丰度转录本的 CSV 文件。
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#read in data----
## Input files
# Calculating differential translation genes (DTGs) requires the count matrices from Ribo-seq and RNA-seq.
# These should be the raw counts, they should not be normalized or batch corrected.
# It also requires a sample information file which should be in the same order as samples in the count matrices.
# It should include information on sequencing type, treatment, batch or any other covariate you need to model.
## 输入文件
# 计算差异翻译基因（DTGs）需要 Ribo-seq 和 RNA-seq 的原始计数矩阵（未做归一化或批次校正），
# 并需要一份与计数矩阵样本顺序一致的样本信息表，其中包含测序类型、处理条件、批次等协变量信息。

#RPFs
#the following for loop reads in each final CDS counts file and renames the counts column by the sample name and saves each data frame to a list
#下面的 for 循环读取每个最终 CDS 计数文件，将计数列重命名为样本名，并保存到列表中。
data_list <- list()
for (sample in RPF_sample_names) {
  df <- read_csv(file = file.path(parent_dir, "Analysis/CDS_counts", paste0(sample, "_pc_final_counts_all_frames.csv")), col_names = T, col_types = c("c","i"))
  colnames(df) <- c("transcript", sample)
  data_list[[sample]] <- df
}

#merge all data within the above list using reduce
#使用 reduce 合并上述列表中的所有数据。
#Using full join retains all transcript but NAs need to be be replaced with 0 as these are transcipts that had 0 counts in that sample
#使用 full join 保留所有转录本，但 NA 表示该样本计数为 0，需要替换为 0。
#DESeq2 needs the transcripts to be as rownames, not as a column
#DESeq2 需要转录本作为行名而不是单独的一列。
data_list %>%
  reduce(full_join, by = "transcript") %>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  left_join(most_abundant_transcripts, by = "transcript") %>%
  relocate("gene") %>%
  select(-c("gene_sym", "transcript")) -> RPF_counts

#Totals
#Totals 计数部分。
#load libraries
#加载所需库。
library(tximport)
library(DESeq2)

#read transcript to gene ID file and rename and reorder
#读取转录本与基因 ID 映射文件，并重命名和整理列顺序。
read_tsv(file = "\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_gene_IDs.txt", col_names = F) %>%
  dplyr::rename(GENEID = X1,
                TXNAME = X2) %>%
  select(TXNAME, GENEID) -> tx2gene

#import rsem data
#导入 RSEM 计数数据。
#set directory where rsem output is located
#设置 RSEM 输出文件所在目录。
rsem_dir <- file.path(parent_dir, 'rsem')

#create a named vector of files (with path)
#创建带样本名的 RSEM 结果文件向量。
files <- file.path(rsem_dir, paste0(Total_sample_names, ".isoforms.results"))
names(files) <- Total_sample_names

#import data with txi
#使用 tximport 导入转录本计数并聚合到基因层面。
txi <- tximport(files, type="rsem", tx2gene=tx2gene)

#make sure counts are as integers
#确保计数为整数。
as.data.frame(txi$counts) %>%
  mutate_all(~as.integer(.)) %>%
  rownames_to_column("gene") -> Total_counts

#create a data frame with the condition/replicate information----
#创建包含处理条件、测序类型和重复信息的数据框。
#you need to make sure this data frame is correct for your samples
#需要根据实际样本设置修改此数据框。
sample_info <- data.frame(row.names = c(RPF_sample_names, Total_sample_names),
                          Condition = factor(c(rep(control, 3), rep(treatment, 3))),
                          SeqType = factor(c(rep("RPFs", 6), rep("RNA", 6))),
                          replicate = factor(c(1:3,1:3)))

print(sample_info)

#merged RPF counts and Totals
#合并 RPF 和 Totals 的基因计数。
RPF_counts %>%
  inner_join(Total_counts, by = "gene") %>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  column_to_rownames("gene") -> merged_data

summary(merged_data)

#check rownames of sample info are in same order as the column names of the merged data
#检查样本信息行名顺序是否与合并计数矩阵列名一致。
table(colnames(merged_data) == row.names(sample_info))

## Detecting differential translation regulation
### DESeq2 object with batch and interaction term in the design
## 检测差异翻译调控
### 在设计矩阵中包含批次和交互项的 DESeq2 对象。

batch <- 1 #set to 1 if batch effect or 0 if not batch effect

if(batch == 1){
  ddsMat <- DESeqDataSetFromMatrix(countData = merged_data,
                                   colData = sample_info, design =~ replicate + Condition + SeqType + Condition:SeqType)
  
}else if(batch == 0){
  ddsMat <- DESeqDataSetFromMatrix(countData = merged_data,
                                   colData = sample_info, design =~ Condition + SeqType + Condition:SeqType)
}else{
  stop("Batch presence should be indicated by 0 or 1 only", call.=FALSE)
}

head(counts(ddsMat))
keep <- rowMeans(counts(ddsMat)) >= 10
table(keep)
ddsMat <- ddsMat[keep,]

#make sure seqtype and condition are set correctly
#确保 SeqType 和 Condition 的因子水平设置正确（RNA 和对照为参考）。
ddsMat$SeqType = relevel(ddsMat$SeqType,"RNA")
ddsMat$Condition = relevel(ddsMat$Condition,control)

#run DESeq
#运行 DESeq 差异分析。
ddsMat <- DESeq(ddsMat)

# Choose the term you want to look at from resultsNames(ddsMat) 
#从 resultsNames(ddsMat) 中选择需要检验的项。
resultsNames(ddsMat)

# paste0("Condition", treatment, ".SeqTypeRPFs") will test for a change in Ribo-seq levels in the treatment vs control
# accounting for changes in RNA-seq levels in treatment vs control
# alpha sets the adjusted p-value
# 该对比项检验在校正 RNA 差异后，处理组 vs 对照在 Ribo-seq 水平上的变化；alpha 为显著性阈值。
res <- results(ddsMat, name=paste0("Condition", treatment, ".SeqTypeRPFs"), alpha = 0.1)
summary(res)

#output summary
#输出结果摘要到文本文件。
sink(file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("TE_", treatment, "_summary.txt")))
summary(res)
sink()

as.data.frame(res[order(res$padj),]) %>%
  rownames_to_column("gene") %>%
  inner_join(most_abundant_transcripts, by = "gene") -> TE_output
write_csv(TE_output, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("TE_", treatment, "_DEseq2.csv")))

#output gene groups
#按照 TE 变化方向输出基因分组列表。
TE_output %>%
  filter(padj < 0.1 & log2FoldChange < 0) %>%
  pull(gene_sym) -> A1_dep_geneIDs

TE_output %>%
  filter(padj < 0.1 & log2FoldChange > 0) %>%
  pull(gene_sym) -> A1_anti_geneIDs

write.table(file = file.path(parent_dir, "Analysis/transcript_IDs/A1_dep_gene_IDs.txt"), col.names = F, row.names = F, quote = F, A1_dep_geneIDs)
write.table(file = file.path(parent_dir, "Analysis/transcript_IDs/A1_antidep_gene_IDs.txt"), col.names = F, row.names = F, quote = F, A1_anti_geneIDs)
