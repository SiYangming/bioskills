#load libraries
#加载库。
library(DESeq2)
library(tidyverse)
library(tximport)
library(vsn)

#read in common variables
#读取通用变量。
source("common_variables.R")

#create a variable for what the treatment is----
#创建处理组和对照组变量。
control <- "WT"
treatment <- "KO"

#read in gene to transcript IDs map and rename and select ENSTM and ENSGM columns----
#读取基因到转录本 ID 的映射，并只保留 ENST/ENSG 两列。
#this is used by DESeq2 and needs to be in this structure
#该映射供 DESeq2 使用，需要保持这种结构。
read_tsv(file = "\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_gene_IDs.txt", col_names = F) %>%
dplyr::rename(GENEID = X1,
              TXNAME = X2) %>%
  select(TXNAME, GENEID) -> tx2gene

#read in the most abundant transcripts per gene csv file----
#读取每个基因最丰度转录本的 CSV 文件。
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#import rsem data----
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

#create a data frame with the condition/replicate information----
#创建包含处理条件和重复信息的数据框。
#you need to make sure this data frame is correct for your samples, the below creates one for a n=3 with EFT226 treatment.
#需要根据自己的样本设计修改此数据框。
sample_info <- data.frame(row.names = Total_sample_names,
                          condition = factor(c(rep(control, 3), rep(treatment, 3))),
                          replicate = factor(c(1:3,1:3)))

#print the data frame to visually check it has been made as expected
#打印数据框以检查是否按预期构建。
sample_info

#make a DESeq data set from imported data----
#从导入的 txi 对象创建 DESeq 数据集。
ddsTxi <- DESeqDataSetFromTximport(txi,
                                   colData = sample_info,
                                   design = ~ condition + replicate)

#pre-filter to remove genes with less than an average of 10 counts across all samples----
#预过滤掉所有样本平均计数小于 10 的基因。
keep <- rowMeans(counts(ddsTxi)) >= 10
table(keep)
ddsTxi <- ddsTxi[keep,]

#make sure levels are set appropriately so that Ctrl is "untreated"
#确保对照组作为参考水平。
ddsTxi$condition <- relevel(ddsTxi$condition, ref = control)

#run DESeq on DESeq data set----
#在数据集上运行 DESeq 差异分析。
dds <- DESeq(ddsTxi)

#extract results for each comparison----
#提取指定对比的差异分析结果。
res <- results(dds, contrast=c("condition", treatment, control))

#summarise results----
#汇总差异分析结果。
summary(res)

#write summary to a text file
#将结果摘要写入文本文件。
sink(file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_DEseq2_summary.txt")))
summary(res)
sink()

#apply LFC shrinkage for each comparison----
#对该对比应用 LFC 收缩。
lfc_shrink <- lfcShrink(dds, coef=paste("condition", treatment, "vs", control, sep = "_"), type="apeglm")

#write reslts to csv----
#将 LFC 收缩后的结果写出为 CSV。
as.data.frame(lfc_shrink[order(lfc_shrink$padj),]) %>%
  rownames_to_column("gene") %>%
  inner_join(most_abundant_transcripts, by = "gene") -> DEseq2_output
write_csv(DEseq2_output, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_DEseq2_apeglm_LFC_shrinkage.csv")))

#extract normalised counts and plot SD vs mean----
#提取标准化计数并绘制标准差与均值关系图。
ntd <- normTransform(dds) #this gives log2(n + 1)
#此转换得到 log2(n + 1)。
vsd <- vst(dds, blind=FALSE) #Variance stabilizing transformation
#方差稳定化转换。
rld <- rlog(dds, blind=FALSE) #Regularized log transformation
#正则化对数转换。

meanSdPlot(assay(ntd))
meanSdPlot(assay(vsd))
meanSdPlot(assay(rld))

#write out normalised counts data----
#导出标准化计数数据。
#Regularized log transformation looks preferable for this data. Check for your own data and select the appropriate one
#对于本数据，正则化对数转换表现更好；请根据自己的数据选择合适方法。
#The aim is for the range of standard deviations to be similar across the range of abundances, i.e. for the red line to be flat
#目标是使各丰度范围内标准差相近，即红线近似水平。
as.data.frame(assay(rld)) %>%
  rownames_to_column("gene") %>%
  inner_join(most_abundant_transcripts, by = "gene") -> normalised_counts
write_csv(normalised_counts, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("Totals_", treatment, "_normalised_counts.csv")))

#plot PCA----
#绘制 PCA 图。
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
#应用批次效应校正并重新绘制 PCA。
mat <- assay(rld)
mat <- limma::removeBatchEffect(mat, rld$replicate)
assay(rld) <- mat

#PCA
#批次校正后的 PCA。
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


