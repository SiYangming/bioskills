#load packages----
# 加载所需 R 包。----
library(tidyverse)

#read in common variables----
# 读取通用变量配置。----
source("common_variables.R")

#read in functions----
# 读取用于归一化与分箱的辅助函数。----
source("binning_RiboSeq_functions.R")

#read in data----
# 读入转录本区域长度信息。----
region_lengths <- read_csv(file = "/home/local/BICR/jwaldron/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_region_lengths.csv", col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))

#read in tpms----
# 读入每个转录本的 TPM，并整理为 tidy 格式。
# 随后与样本信息表（来自 common_variables）合并以获得 condition 与 replicate 信息。
read_csv(file = file.path(parent_dir, "Analysis/DESeq2_output/tpms.csv")) %>%
  select(transcript, Total_sample_names) %>%
  gather(key = sample, value = tpm, all_of(Total_sample_names)) %>%
  inner_join(Total_sample_info, by = "sample") -> tpms

#read in counts data----
# 读取 RPF 计数并结合 TPM 对每个转录本进行归一化。----
counts_list <- list()
for (sample in RPF_sample_names) {
  
  #extract the condition and replicate from the sample name (this may need to be edited depending on how your sample names are structured)
  # 从样本名中提取条件与重复信息（需根据实际命名规则调整）。
  condition <- RPF_sample_info$condition[RPF_sample_info$sample == sample]
  replicate <- RPF_sample_info$replicate[RPF_sample_info$sample == sample]
  
  #get all the csv file names from the directory and filter
  # 读取计数文件并追加 condition/replicate 信息，然后调用 normalise_data 完成归一化。
  read_csv(file = file.path(parent_dir, "Counts_files/csv_files", paste0(sample, "_pc_final_counts.csv"))) %>%
    mutate(condition = rep(condition),
           replicate = rep(replicate)) %>%
    normalise_data(tpms = tpms) -> counts_list[[sample]]
}

#save list----
# 保存归一化后的 counts 列表，供后续绘制单基因 meta plots 使用。----
save(file = file.path(parent_dir, "Counts_files/R_objects/counts_list.Rdata"), counts_list)
