#load packages----
# 加载绘图与数据处理相关包。----
library(tidyverse)
library(grid)
library(gridExtra)

#read in common variables
# 读取通用变量配置。
source("common_variables.R")

#set what you have called your control and treated samples. This can be a vector of strings if more than one treatment has been used.
# 设置对照组与处理组名称；如有多个处理条件，可使用字符串向量。
control <- "WT"
treatment <- "KO"

#read in functions----
# 读取用于归一化、分箱和绘图的辅助函数。----
source("binning_RiboSeq_functions.R")

#create themes----
# 定义单转录本展示用的绘图主题。----
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
# 读取归一化后的 counts 列表以及转录本长度信息。----
load(file = file.path(parent_dir, "Counts_files/R_objects/counts_list.Rdata"))

most_abundant_transcripts <- read_csv(file = file.path(parent_dir, "Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv"))
region_lengths <- read_csv(file = "\\\\data.beatson.gla.ac.uk/data/R11/bioinformatics_resources/FASTAs/mouse/GENCODE/vM27/transcript_info/gencode.vM27.pc_transcripts_region_lengths.csv", col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len"))

#run on an individual genes----
# 在单个候选基因上绘制 meta 图。----

#dir is sub directory (within "plots/binned_plots/single_transcripts" where plots will be saved. It will create directory if it does not already exist)
# plot 结果将保存在 "plots/binned_plots/single_transcripts" 下的子目录 dir 中，如不存在会自动创建。
#plot_binned/plot_single_nt sets whether to plot either or both of these
# plot_binned / plot_single_nt 控制是否绘制分箱曲线和单核苷酸曲线。
#SD=T will add standard deviation bars to line plots, set to false if not wanted
# SD = T 时在线图中添加标准差；如不需要可设为 FALSE。
#plot_replicates=T will create a seperate binned plot with individual replicates rather than average
# plot_replicates = T 会额外绘制各重复的独立分箱曲线。
#control and treatment need to state what you have called your control and treatment samples. You can specificy more than one treatment as a vector, but you will have to set plot_delta=F
# control 与 treatment 需与 common_variables 中的条件名称一致；如 treatment 为向量，需将 plot_delta 设为 FALSE。
#keep paired_data=T if data is paired, otherwise set to F. This is for calculating 95% confidence intervals for the delta plots
# 若样本成对设计（paired），保持 paired_data = T 以计算 delta 图的 95% 置信区间；否则设为 FALSE。
#region_cutoffs = c(0,0,0) will mean any transcript length can be plotted. For meta plots, this is normally set to region_cutoffs = c(50,300,50)
# region_cutoffs = c(0,0,0) 允许任意长度转录本参与绘图；meta 分析时通常设为 c(50,300,50)。
plot_single_transcripts(gene = "Ctnnb1", dir = "candidate",
                        plot_binned = T, plot_single_nt = T, plot_codons = T,
                        SD = T, plot_replicates = T, plot_delta = T,
                        control = control, treatment = treatment, paired_data = T,
                        region_cutoffs = c(0,0,0))

#read in DEseq2 output----
read_csv(file.path(parent_dir, "Analysis/DESeq2_output/merged_DESeq2.csv")) %>%
  inner_join(most_abundant_transcripts, by = "gene") %>%
  mutate(RPFs_group = factor(RPFs_group),
         TE_group = factor(TE_group)) -> DESeq2_df
summary(DESeq2_df)

#extract IDs
DESeq2_df %>%
  filter(RPFs_group == "RPFs down") %>%
  top_n(n = -100, wt = RPFs_padj) %>%
  top_n(n = -50, wt = RPFs_log2FC) %>%
  pull(gene_sym) -> RPFs_down_IDs

DESeq2_df %>%
  filter(RPFs_group == "RPFs up") %>%
  top_n(n = -100, wt = RPFs_padj) %>%
  top_n(n = 50, wt = RPFs_log2FC) %>%
  pull(gene_sym) -> RPFs_up_IDs

#run on gene lists
lapply(RPFs_down_IDs, plot_single_transcripts, dir = "RPFs_down",
       plot_binned = T, plot_single_nt = F, plot_codons = F,
       SD = T, plot_replicates = F, plot_delta = F,
       control = control, treatment = treatment, paired_data = T,
       region_cutoffs = c(0,0,0))

lapply(RPFs_up_IDs, plot_single_transcripts, dir = "RPFs_up",
       plot_binned = T, plot_single_nt = F, plot_codons = F,
       SD = T, plot_replicates = F, plot_delta = F,
       control = control, treatment = treatment, paired_data = T,
       region_cutoffs = c(0,0,0))
