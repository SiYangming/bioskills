#load packages----
# 加载所需 R 包。----
library(tidyverse)

#read in common variables----
# 读取通用变量配置。----
source("common_variables.R")

#set the threshold for the average CDS counts a transcript has to have across all samples for it to be included
# 设置纳入分析所需的平均 CDS 计数阈值（跨所有样本的均值）。
min_counts <- 50

#set the thresholds for region lengths
# 设置各区域长度阈值。
UTR5_min_len <- 25
CDS_min_len <- 300
UTR3_min_len <- 0

# region_cutoffs 向量按 5'UTR、CDS、3'UTR 顺序给出最小长度。
region_cutoffs <- c(UTR5_min_len, CDS_min_len, UTR3_min_len)

#read in functions----
# 读取用于分箱与归一化的辅助函数。----
source("binning_RiboSeq_functions.R")

#read in data----
# 读入各转录本 UTR/CDS 区域长度信息。----
region_lengths <- read_csv(file = "/home/local/BICR/jwaldron/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_region_lengths.csv", col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))
#region_lengths <- read_csv(file = "\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_region_lengths.csv", col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))

#read in tpms----
# 读入每个转录本的 TPM，并整理为 tidy 格式。
# 随后与样本信息表（来自 common_variables）合并以获得 condition 与 replicate 信息。
read_csv(file = file.path(parent_dir, "Analysis/DESeq2_output/tpms.csv")) %>%
  select(transcript, Total_sample_names) %>%
  gather(key = sample, value = tpm, all_of(Total_sample_names)) %>%
  inner_join(Total_sample_info, by = "sample") -> tpms

#sanity check----
# 进行数据合理性检查：每个样本内所有转录本 TPM 之和应为 1,000,000。
tpms %>%
  group_by(condition, replicate) %>%
  summarise(summed_tpm = sum(tpm))

#read in the CDS counts
# 使用 for 循环读入每个样本的 CDS 计数文件，将计数列重命名为样本名，并保存到列表中。
data_list <- list()
for (sample in RPF_sample_names) {
  df <- read_csv(file = file.path(parent_dir, "Analysis/CDS_counts", paste0(sample, "_pc_final_counts_all_frames.csv")), col_names = T)
  colnames(df) <- c("transcript", sample)
  data_list[[sample]] <- df
}

#extract transcript IDs to keep----
# 提取需要保留的转录本 ID。----
# 1) 使用 reduce 合并上述列表中的所有数据；
# 2) 去除任一样本中为 NA 的转录本（表示计数为 0）；
# 3) 去除跨样本平均计数低于 min_counts 的转录本；
# 4) 根据前面定义的长度阈值过滤过短的 UTR/CDS；
# 5) 提取最终通过过滤的转录本 ID。
data_list %>%
  reduce(full_join, by = "transcript") %>%
  column_to_rownames("transcript") %>%
  drop_na() %>%
  filter(rowMeans(.) >= min_counts) %>%
  rownames_to_column("transcript") %>%
  inner_join(region_lengths, by = "transcript") %>%
  filter(UTR5_len >= UTR5_min_len & CDS_len >= CDS_min_len & UTR3_len >= UTR3_min_len) %>%
  pull(transcript) -> filtered_transcripts

#read in counts data----
# 读取各样本的转录本位点计数，并进行归一化。----
counts_list <- list()
for (sample in RPF_sample_names) {
  
  #extract the condition and replicate from the sample name (this may need to be edited depending on how your sample names are structured)
  # 从样本名中提取条件与重复编号（视具体命名结构可能需要调整）。
  condition <- RPF_sample_info$condition[RPF_sample_info$sample == sample]
  replicate <- RPF_sample_info$replicate[RPF_sample_info$sample == sample]
  
  #get all the csv file names from the directory and filter
  # 从目录中读取计数文件，过滤到目标转录本，并追加条件与重复信息后进行归一化。
  read_csv(file = file.path(parent_dir, "Counts_files/csv_files", paste0(sample, "_pc_final_counts.csv"))) %>%
    filter(transcript %in% filtered_transcripts) %>%
    mutate(condition = rep(condition),
           replicate = rep(replicate)) %>%
    normalise_data(tpms = tpms) -> counts_list[[sample]]
}

#return to parent directory
# 切换回父目录。
setwd(parent_dir)

#check counts list looks OK
# 粗略检查一个样本的数据结构是否合理。
summary(counts_list[[1]])
head(counts_list[[1]])

#sanity check----
# 再次进行合理性检查：每个样本所有转录本的 CPM 之和应为 1,000,000。
sum_sample_counts <- function(df) {
  df %>%
    summarise(summed_counts = sum(CPM)) -> df2
  
  return(df2)
}

lapply(counts_list, sum_sample_counts)

#bin all data----
# 对所有转录本的信号进行区域分箱（5'UTR / CDS / 3'UTR）。----
binned_list <- lapply(counts_list, bin_data, region_lengths = region_lengths, region_cutoffs = region_cutoffs, bins = c(25,50,25))
summary(binned_list[[1]])
head(binned_list[[1]])

#remove outliers----
# 计算每个条件下、各转录本在所有重复中的标准差，用于识别离群转录本。----
do.call("rbind", binned_list) %>%
  group_by(transcript, condition, region, bin) %>%
  summarise(binned_normalised_cpm_sd = sd(binned_normalised_cpm),
            binned_cpm_sd = sd(binned_cpm)) -> transcript_SDs

summary(transcript_SDs)

n_distinct(transcript_SDs$transcript[is.na(transcript_SDs$binned_cpm_sd)])
n_distinct(transcript_SDs$transcript)

# 计算标准差分布在 0.95–1 范围内的分位数，用于挑选阈值。
sd_quantiles <- data.frame(quantile = seq(0.95, 1, 0.00001),
                           binned_normalised_cpm_sd = quantile(transcript_SDs$binned_normalised_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T),
                           binned_cpm_sd = quantile(transcript_SDs$binned_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T))

#plot all SD quantiles
# 绘制标准差分位数曲线，辅助选择离群阈值。
png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/binned_normalised_cpm_sd_quantiles_pre_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, binned_normalised_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/binned_cpm_sd_quantiles_pre_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, binned_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

#extract transcripts with a binned SD above a quantile threshold
# 按分位阈值提取高波动（高 SD）的转录本作为离群值。
# 例如 0.99 将移除 SD 排名前 1% 的转录本；需根据实际保留转录本数量调整该参数。
perc <- 1 - 0.00003

normalised_cpm_discard_transcripts <- transcript_SDs$transcript[transcript_SDs$binned_normalised_cpm_sd >= quantile(transcript_SDs$binned_normalised_cpm_sd, probs = perc, na.rm = T)]
cpm_discard_transcripts <- transcript_SDs$transcript[transcript_SDs$binned_cpm_sd >= quantile(transcript_SDs$binned_cpm_sd, probs = perc, na.rm = T)]
discard_transcripts <- unique(c(normalised_cpm_discard_transcripts, cpm_discard_transcripts))
paste(length(discard_transcripts), "outliers to be removed")

#remove outliers from counts list and re-normalise
# 从每个样本的计数表中移除离群转录本，并重新进行 TPM 归一化。
for (i in 1:length(counts_list)) {
  counts_list[[i]] <- counts_list[[i]][!(counts_list[[i]]$transcript %in% discard_transcripts),]
  counts_list[[i]] <- normalise_data(counts_list[[i]], tpms = tpms)
}

summary(counts_list[[1]])
head(counts_list[[1]])

#bin all data again having removed the outliers
# 在移除离群值后再次进行区域分箱。
binned_list <- lapply(counts_list, bin_data, region_lengths = region_lengths, region_cutoffs = region_cutoffs, bins = c(25,50,25))
summary(binned_list[[1]])
head(binned_list[[1]])

#plot quantiles of SD again to check all outliers have been removed
# 再次计算并绘制 SD 分位数，用于确认离群转录本已被有效移除。
do.call("rbind", binned_list) %>%
  group_by(transcript, condition, region, bin) %>%
  summarise(binned_normalised_cpm_sd = sd(binned_normalised_cpm),
            binned_cpm_sd = sd(binned_cpm)) -> transcript_SDs

# 重新计算过滤后数据的 SD 分位数。
sd_quantiles <- data.frame(quantile = seq(0.95, 1, 0.00001),
                           binned_normalised_cpm_sd = quantile(transcript_SDs$binned_normalised_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T),
                           binned_cpm_sd = quantile(transcript_SDs$binned_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T))

#plot all SD quantiles
# 绘制过滤后 SD 分布曲线以再次评估离群情况。
png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/binned_normalised_cpm_sd_quantiles_post_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, binned_normalised_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/binned_cpm_sd_quantiles_post_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, binned_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

#single nt----
# 基于单核苷酸分辨率生成 meta profile。----
single_nt_list <- lapply(counts_list, splice_single_nt, region_lengths = region_lengths)
summary(single_nt_list[[1]])
head(single_nt_list[[1]])

#plot quantiles of SD again to check all outliers have been removed
# 对单核苷酸信号同样计算 SD 分位数，查看是否仍有高波动转录本。
do.call("rbind", single_nt_list) %>%
  group_by(transcript, condition, region, window) %>%
  summarise(single_nt_normalised_cpm_sd = sd(single_nt_normalised_cpm),
            single_nt_cpm_sd = sd(single_nt_cpm)) -> transcript_SDs

# 构建单核苷酸层面的 SD 分位数数据框。
sd_quantiles <- data.frame(quantile = seq(0.95, 1, 0.00001),
                           single_nt_normalised_cpm_sd = quantile(transcript_SDs$single_nt_normalised_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T),
                           single_nt_cpm_sd = quantile(transcript_SDs$single_nt_cpm_sd, probs = seq(0.95, 1, 0.00001), na.rm = T))

#plot all SD quantiles
# 绘制单核苷酸信号的 SD 分布曲线。
png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/single_nt_normalised_cpm_sd_quantiles_post_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, single_nt_normalised_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

png(filename = file.path(parent_dir, "plots/binned_plots/normalisation/single_nt_cpm_sd_quantiles_post_filtering.png"))
sd_quantiles %>%
  ggplot(aes(quantile, single_nt_cpm_sd))+
  geom_point()+
  theme_classic()
dev.off()

#save lists----
# 将分箱结果和单核苷酸结果保存为 R 对象以供后续绘图脚本使用。----
save(file = file.path(parent_dir, "Counts_files/R_objects/binned_list.Rdata"), binned_list)
save(file = file.path(parent_dir, "Counts_files/R_objects/single_nt_list.Rdata"), single_nt_list)
