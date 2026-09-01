#load libraries
#加载库。
library(tidyverse)

#read in common variables
#读取通用变量。
source("common_variables.R")

myTheme <- theme_classic()+
  theme(axis.title.y = element_text(size = 18),
        axis.title.x = element_blank(),
        axis.text = element_text(size = 16),
        plot.title = element_text(size = 20, face = "bold", hjust = 0.5),
        legend.text = element_text(size = 18),
        legend.title = element_blank())


#read in read counts summaries----
#读取各样本的 reads 计数汇总。
data_list <- list()
for (sample in Total_sample_names) {
  read_csv(file = file.path(parent_dir, "logs", paste0(sample, "_read_counts.csv"))) %>%
    mutate(sample = rep(sample)) %>%
    inner_join(Total_sample_info, by = "sample") -> data_list[[sample]]
}

Totals_counts <- do.call("rbind", data_list)

write_csv(file = file.path(parent_dir, "logs/Totals_reads_summary.csv"), Totals_counts)

#plot total counts----
#绘制输入 reads 总数柱状图。
Totals_counts %>%
  ggplot(aes(x = condition, y = cutadapt_in, fill = replicate))+
  geom_col(position = position_dodge())+
  ylab("all counts")+
  ggtitle("Totals")+
  myTheme -> Totals_counts_plot

png(filename = file.path(parent_dir, "plots/read_counts_summary/Totals_all_counts.png"), width = 500, height = 300)
print(Totals_counts_plot)
dev.off()

#plot cutadapt counts %----
#绘制度后保留 reads 的百分比。
Totals_counts %>%
  mutate(cutadapt_perc = (cutadapt_out / cutadapt_in) * 100) %>%
  ggplot(aes(x = condition, y = cutadapt_perc, fill = replicate))+
  geom_col(position = position_dodge())+
  ylab("trimmed reads %")+
  ylim(c(0,100))+
  ggtitle("Totals")+
  myTheme -> Totals_cutadapt_plot

png(filename = file.path(parent_dir, "plots/read_counts_summary/Totals_cutadapt_counts.png"), width = 500, height = 300)
print(Totals_cutadapt_plot)
dev.off()

#pc %----
#绘制比对到 pc 的 reads 百分比。
Totals_counts %>%
  mutate(pc_perc = (pc_out / pc_in) * 100) %>%
  ggplot(aes(x = condition, y = pc_perc, fill = replicate))+
  geom_col(position = position_dodge())+
  ylab("pc reads %")+
  ylim(c(0,100))+
  ggtitle("Totals")+
  myTheme -> Totals_pc_alignment_plot

png(filename = file.path(parent_dir, "plots/read_counts_summary/Totals_pc_alignments.png"), width = 500, height = 300)
print(Totals_pc_alignment_plot)
dev.off()

#plot unique counts %----
#绘制去重后 pc 唯一 reads 的百分比。
Totals_counts %>%
  mutate(unique_perc = (deduplication_out / deduplication_in) * 100) %>%
  ggplot(aes(x = condition, y = unique_perc, fill = replicate))+
  geom_col(position = position_dodge())+
  ylab("Unique pc reads %")+
  ylim(c(0,100))+
  ggtitle("Totals")+
  myTheme -> Totals_deduplication_plot

png(filename = file.path(parent_dir, "plots/read_counts_summary/Totals_deduplication_counts.png"), width = 500, height = 300)
print(Totals_deduplication_plot)
dev.off()

#final pc counts----
#绘制最终 pc 唯一 reads 的绝对数。
Totals_counts %>%
  ggplot(aes(x = condition, y = deduplication_out, fill = replicate))+
  geom_col(position = position_dodge())+
  ylab("Total unique pc reads")+
  ggtitle("Totals")+
  myTheme -> Totals_pc_count_plot

png(filename = file.path(parent_dir, "plots/read_counts_summary/Totals_pc_counts.png"), width = 500, height = 300)
print(Totals_pc_count_plot)
dev.off()
