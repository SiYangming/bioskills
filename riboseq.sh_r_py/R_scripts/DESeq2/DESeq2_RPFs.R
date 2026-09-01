#load libraries
#加载库。
library(DESeq2)
library(tidyverse)
library(vsn)

#read in common variables
#读取通用变量。
source("common_variables.R")

#create a variable for what the treatment is----
#创建一个变量表示处理组。
control <- "WT"
treatment <- "KO"

#read in the most abundant transcripts per gene csv file----
#读取每个基因最丰度转录本的 CSV 文件。
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#read in data----
#读取数据。
#the following for loop reads in each final CDS counts file and renames the counts column by the sample name and saves each data frame to a list
#下面的 for 循环读取每个最终 CDS 计数文件，将计数列重命名为样本名，并保存到列表中。
data_list <- list()
for (sample in RPF_sample_names) {
  df <- read_csv(file = file.path(parent_dir, "Analysis/CDS_counts", paste0(sample, "_pc_final_counts_all_frames.csv")), col_names = T)
  colnames(df) <- c("transcript", sample)
  data_list[[sample]] <- df
}

#merge all data within the above list using reduce
#使用 reduce 合并上述列表中的所有数据。
#Using full join retains all transcripts, but the NAs need to be replaced with 0 as these are transcipts that had 0 counts in that sample
#使用 full join 保留所有转录本，但 NA 表示该样本计数为 0，需要替换为 0。
#DESeq2 needs the transcripts to be as rownames, not as a column
#DESeq2 需要转录本作为行名而不是单独的一列。
data_list %>%
  reduce(full_join, by = "transcript") %>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  column_to_rownames("transcript") -> RPF_counts

#create a data frame with the condition/replicate information----
#创建包含处理条件和重复信息的数据框。
#you need to make sure this data frame is correct for your samples, the below creates one for a n=3 with EFT226 treatment.
#需要确保该数据框与实际样本设置一致，下面示例为 n=3 的处理设计。
sample_info <- data.frame(row.names = RPF_sample_names,
                          condition = factor(c(rep(control, 3), rep(treatment, 3))),
                          replicate = factor(c(1:3,1:3)))

#print the data frame to visually check it has been made as expected
#打印数据框以可视化检查是否按预期构建。
sample_info

#make a DESeq data set from imported data----
#从导入的数据创建 DESeq 数据集。
DESeq2data <- DESeqDataSetFromMatrix(countData = RPF_counts,
                                     colData = sample_info,
                                     design = ~ replicate + condition)

#pre-filter to remove genes with less than an average of 10 counts across all samples----
#预过滤掉所有样本平均计数小于 10 的基因。
keep <- rowMeans(counts(DESeq2data)) >= 10
table(keep)
DESeq2data <- DESeq2data[keep,]

#make sure levels are set appropriately so that Ctrl is "untreated"
#确保因子水平设置正确，使 Ctrl 作为“未处理”参考水平。
DESeq2data$condition <- relevel(DESeq2data$condition, ref = control)

#run DESeq on DESeq data set----
#在 DESeq 数据集上运行差异分析。
dds <- DESeq(DESeq2data)

#extract results for each comparison----
#提取指定比较的差异分析结果。
res <- results(dds, contrast=c("condition", treatment, control))

#summarise results----
#汇总差异分析结果。
summary(res)

#write summary to a text file
#将结果汇总写入文本文件。
sink(file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_DEseq2_summary.txt")))
summary(res)
sink()

#apply LFC shrinkage for each comparison----
#对该比较应用 LFC 收缩。
lfc_shrink <- lfcShrink(dds, coef=paste("condition", treatment, "vs", control, sep = "_"), type="apeglm")

#write reslts to csv----
#将 LFC 收缩后的结果写入 CSV 文件。
as.data.frame(lfc_shrink[order(lfc_shrink$padj),]) %>%
  rownames_to_column("transcript") %>%
  inner_join(most_abundant_transcripts, by = "transcript") -> DEseq2_output
write_csv(DEseq2_output, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_DEseq2_apeglm_LFC_shrinkage.csv")))

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
#目标是各丰度范围内标准差范围相近，即红线近似水平。
as.data.frame(assay(rld)) %>%
  rownames_to_column("transcript") %>%
  inner_join(most_abundant_transcripts, by = "transcript") -> normalised_counts
write_csv(normalised_counts, file = file.path(parent_dir, "Analysis/DESeq2_output", paste0("RPFs_", treatment, "_normalised_counts.csv")))

#plot PCA----
#绘制 PCA 图。
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
#应用批次效应校正并重新绘制热图和 PCA。
mat <- assay(rld)
mat <- limma::removeBatchEffect(mat, rld$replicate)
assay(rld) <- mat

#PCA
#批次校正后的 PCA。
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


