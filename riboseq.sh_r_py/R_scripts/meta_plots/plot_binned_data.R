#load packages----
# 加载绘图与数据处理相关包。----
library(tidyverse)
library(grid)
library(gridExtra)
library(viridis)

#read in common variables----
# 读取通用变量配置。----
source("common_variables.R")

#set what you have called your control and treated samples. This can be a vector of strings if more than one treatment has been used.
# 设置对照组与处理组名称；如有多个处理条件，可使用字符串向量。
control <- "WT"
treatment <- "KO"

#read in functions----
# 读取用于归一化、分箱和绘图的辅助函数。----
source("binning_RiboSeq_functions.R")

#create themes----
# 定义用于 meta 图的基础主题。----
my_theme <- theme_bw()+
  theme(panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank(),
        axis.title = element_blank())

UTR5_theme <- my_theme+
  theme(legend.position="none",
        axis.ticks.x = element_blank(),
        axis.text.y = element_text(size = 18),
        axis.text.x = element_blank())

CDS_theme <- my_theme+
  theme(legend.position="none",
        axis.ticks = element_blank(),
        axis.text = element_blank())

UTR3_theme <- my_theme+
  theme(axis.ticks = element_blank(),
        axis.text = element_blank(),
        legend.text = element_text(size = 18),
        legend.title = element_blank())

#read in data----
# 读入分箱后的 RPF 信号与单核苷酸信号。----
load(file = file.path(parent_dir, "Counts_files/R_objects/binned_list.Rdata"))
summary(binned_list[[1]])
head(binned_list[[1]])

load(file = file.path(parent_dir, "Counts_files/R_objects/single_nt_list.Rdata"))
summary(single_nt_list[[1]])
head(single_nt_list[[1]])

region_lengths <- read_csv(file = "\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_region_lengths.csv", col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))
most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))

#all transcripts----
# 全部转录本的 meta 分析。----
#summarise
#summarise within each sample
# 先在每个样本内按 bin 汇总。
summarised_binned_list <- lapply(binned_list, summarise_data, value = "binned_cpm", grouping = "bin")
summary(summarised_binned_list[[1]])
print(summarised_binned_list[[1]])

#summarise within each condition (across replicates)
# 再在条件层面（跨重复）汇总均值和标准差。
do.call("rbind", summarised_binned_list) %>%
  group_by(grouping, condition, region) %>%
  summarise(average_counts = mean(mean_counts),
            sd_counts = sd(mean_counts)) %>%
  ungroup() -> summarised_binned
summary(summarised_binned)
print(summarised_binned)

#plot lines
# 绘制 5'UTR / CDS / 3'UTR 的分箱平均覆盖曲线（带 SD）。----
binned_line_plots <- plot_binned_lines(df = summarised_binned, SD = T, control = control, treatment = treatment)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts binned lines.png"), width = 1000, height = 300)
grid.arrange(binned_line_plots[[1]], binned_line_plots[[2]], binned_line_plots[[3]], nrow = 1, widths = c(1,2,1.5))
dev.off()

#plot each replicate
# 绘制包含所有重复样本的分箱曲线。----
binned_line_plots_all_replicates <- plot_binned_all_replicates(summarised_binned_list, control = control, treatment = treatment)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts binned lines all replicates.png"), width = 1000, height = 300)
grid.arrange(binned_line_plots_all_replicates[[1]], binned_line_plots_all_replicates[[2]], binned_line_plots_all_replicates[[3]], nrow = 1, widths = c(1,2,1.5))
dev.off()

#calculate and plot delta
# 计算处理组与对照组之间的差值（delta），并绘制 delta 曲线。----
binned_delta_data <- calculate_binned_delta(binned_list, value = "binned_cpm", control = control, treatment = treatment, paired_data = F)
binned_delta_plots <- plot_binned_delta(binned_delta_data)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts binned delta.png"), width = 1000, height = 200)
grid.arrange(binned_delta_plots[[1]], binned_delta_plots[[2]], binned_delta_plots[[3]],
             nrow = 1, widths = c(1,2,1))
dev.off()

#positional----
# 位置归一化分析：先在单个转录本内归一化，再在样本与条件层面汇总。----
#normalise within each transcript
positional_list <- lapply(binned_list, calculate_positional_counts)

#summarise within each sample
# 在样本内按 bin 汇总位置归一化计数。
summarised_positional_list <- lapply(positional_list, summarise_data, value = "positional_counts", grouping = "bin")

#summarise within each condition (across replicates)
# 在条件层面（跨重复）汇总均值和标准差。
do.call("rbind", summarised_positional_list) %>%
  group_by(grouping, condition) %>%
  summarise(average_counts = mean(mean_counts),
            sd_counts = sd(mean_counts)) %>%
  ungroup() -> summarised_positional

#plot
# 绘制位置归一化后的平均轨迹（带 SD）。----
positional_line_plots <- plot_positional_lines(df = summarised_positional, SD = T, control = control, treatment = treatment)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts binned positional lines.png"), width = 500, height = 200)
print(positional_line_plots)
dev.off()

#calculate and plot delta
# 计算位置归一化信号的 delta 并作图。----
binned_positional_delta <- calculate_positional_delta(positional_list, control = control, treatment = treatment, paired_data = F)
positional_binned_delta_plots <- plot_positional_delta(binned_positional_delta)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts binned positional delta.png"), width = 500, height = 200)
print(positional_binned_delta_plots)
dev.off()

#single nt----
# 单碱基分辨率 meta 分析。----
#summarise
# 在样本内按 window 汇总单碱基 CPM。
summarised_single_nt_list <- lapply(single_nt_list, summarise_data, value = "single_nt_cpm", grouping = "window")
summary(summarised_single_nt_list[[1]])
print(summarised_single_nt_list[[1]])

do.call("rbind", summarised_single_nt_list) %>%
  group_by(grouping, condition, region) %>%
  summarise(average_counts = mean(mean_counts),
            sd_counts = sd(mean_counts)) %>%
  ungroup() -> summarised_single_nt
summary(summarised_single_nt)
print(summarised_single_nt)

#plot
# 绘制单碱基覆盖曲线（按区域拆分）。----
single_nt_line_plots <- plot_single_nt_lines(summarised_single_nt, SD=T, plot_ends=F, control = control, treatment = treatment)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts single nt lines.png"), width = 1300, height = 300)
grid.arrange(single_nt_line_plots[[1]], single_nt_line_plots[[2]], single_nt_line_plots[[3]], single_nt_line_plots[[4]], nrow = 1, widths = c(1,2,2,1.5))
dev.off()

#calculate and plot delta
# 计算单碱基 CPM 的 delta 并作图。----
single_nt_delta_data <- calculate_single_nt_delta(single_nt_list, value = "single_nt_cpm", control = control, treatment = treatment, paired_data = F)
single_nt_delta_plots <- plot_single_nt_delta(single_nt_delta_data, SD = T)

png(filename = file.path(parent_dir, "plots/binned_plots/all_transcripts/all transcripts single nt delta.png"), width = 1300, height = 200)
grid.arrange(single_nt_delta_plots[[1]], single_nt_delta_plots[[2]], single_nt_delta_plots[[3]], single_nt_delta_plots[[4]], nrow = 1, widths = c(1,2,2,1))
dev.off()

#Dep vs Antidep vs Indep----
# 依赖型/抗依赖型/独立型转录本的分组 meta 分析。----
#read in DESeq2 output
# 读取 DESeq2 输出并按照 TE/RPFs 分组。----
read_csv(file = file.path(parent_dir, "Analysis/DESeq2_output/merged_DESeq2.csv")) %>%
  inner_join(most_abundant_transcripts, by = c("gene", "gene_sym")) %>%
  mutate(RPFs_group = factor(RPFs_group),
         TE_group = factor(TE_group)) -> DESeq2_data

summary(DESeq2_data)

#plot to check groupings
# 绘制 RPFs vs Totals 的散点图以检查分组是否合理。
DESeq2_data %>%
  ggplot(aes(x = totals_log2FC, y = RPFs_log2FC, colour = RPFs_group))+
  geom_point()

#plot to check groupings
# 使用 TE 分组进行同样的检查。
DESeq2_data %>%
  filter(!(is.na(TE_group))) %>%
  ggplot(aes(x = totals_log2FC, y = RPFs_log2FC, colour = TE_group))+
  geom_point()

#extract transcript IDs
# 提取不同响应类型的转录本 ID 列表。----
RPFs_down_IDs <- DESeq2_data$transcript[DESeq2_data$RPFs_group == "RPFs down" & !(is.na(DESeq2_data$RPFs_group))]
RPFs_up_IDs <- DESeq2_data$transcript[DESeq2_data$RPFs_group == "RPFs up" & !(is.na(DESeq2_data$RPFs_group))]

TE_down_IDs <- DESeq2_data$transcript[DESeq2_data$TE_group == "TE down" & !(is.na(DESeq2_data$TE_group))]
TE_up_IDs <- DESeq2_data$transcript[DESeq2_data$TE_group == "TE up" & !(is.na(DESeq2_data$TE_group))]

no_change_IDs <- DESeq2_data$transcript[DESeq2_data$TE_group == "no change" & !(is.na(DESeq2_data$TE_group))]

#plot binned
# 针对不同亚群（RPFs 下调/上调、TE 下调/上调、无变化）生成分箱 meta 图和 delta 图。----
plot_subset(IDs = RPFs_down_IDs, subset = "RPFs-down", sub_dir = "Dep",
            control = control, treatment = treatment,
            binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
            plot_binned = T, plot_single_nt = F, plot_positional = F,
            plot_replicates = T, plot_delta = T, SD = T, paired_data = F)

plot_subset(IDs = RPFs_up_IDs, subset = "RPFs-up", sub_dir = "Dep",
            control = control, treatment = treatment,
            binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
            plot_binned = T, plot_single_nt = F, plot_positional = F,
            plot_replicates = T, plot_delta = T, SD = T, paired_data = F)

plot_subset(IDs = TE_down_IDs, subset = "TE-down", sub_dir = "Dep",
            control = control, treatment = treatment,
            binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
            plot_binned = T, plot_single_nt = F, plot_positional = F,
            plot_replicates = T, plot_delta = T, SD = T, paired_data = F)

plot_subset(IDs = TE_up_IDs, subset = "TE-up", sub_dir = "Dep",
            control = control, treatment = treatment,
            binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
            plot_binned = T, plot_single_nt = F, plot_positional = F,
            plot_replicates = T, plot_delta = T, SD = T, paired_data = F)

plot_subset(IDs = no_change_IDs, subset = "no_change", sub_dir = "Dep",
            control = control, treatment = treatment,
            binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
            plot_binned = T, plot_single_nt = F, plot_positional = F,
            plot_replicates = T, plot_delta = T, SD = T, paired_data = F)

#plot heatmaps
# 为 TE 下调与 TE 上调集合生成分箱热图。----
TE_down_heatmap <- plot_binned_heatmaps(IDs = TE_down_IDs, col_lims = c(-0.02, 0.01), control = control, treatment = treatment, value = "binned_normalised_cpm")
TE_up_heatmap <- plot_binned_heatmaps(IDs = TE_up_IDs, col_lims = c(-0.01, 0.02), control = control, treatment = treatment, value = "binned_normalised_cpm")

png(filename = file.path(parent_dir, "plots/binned_plots/Dep", paste(treatment, "TE-down binned heatmap.png")), width = 1000, height = 1000)
print(TE_down_heatmap)
dev.off()

png(filename = file.path(parent_dir, "plots/binned_plots/Dep", paste(treatment, "TE-up binned heatmap.png")), width = 1000, height = 1000)
print(TE_up_heatmap)
dev.off()

#GSEA pathways----
# 利用 GSEA 通路集合绘制特定路径的 meta 覆盖曲线。----
library(fgsea)

#read in pathways
# 读取 GSEA 通路注释（此处为小鼠 hallmark 通路，路径需按实际环境修改）。----
source("\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/GSEA/read_mouse_GSEA_pathways.R")

#hallmark
#read in fgsea output
# 读入 fgsea 结果对象。----
load(file = file.path(parent_dir, "Analysis/fgsea/hallmark_results.Rdata"))

#extract transcript IDs
# 提取显著富集（padj < 0.05）的 hallmark 通路名称。----
hallmark_pathways <- hallmark_results[[3]]$pathway[hallmark_results[[3]]$padj < 0.05]

lapply(hallmark_pathways, plot_GSEA_binned,
       GSEA_set = pathways.hallmark, sub_dir = "hallmark",
       control = control, treatment = treatment,
       binned_value = "binned_normalised_cpm", single_nt_value = "single_nt_normalised_cpm",
       plot_binned = T, plot_single_nt = F, plot_positional = F,
       plot_delta = T, SD = T, paired_data = F)



