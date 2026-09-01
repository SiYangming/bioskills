#load packages----
#加载依赖包。
library(tidyverse)
library(grid)
library(gridExtra)

#read in common variables----
#读取通用变量。
source("common_variables.R")

#read in data----
#读取区域长度信息。
region_lengths_dir <- "path/to/file" # add the path to the file here
#在此填入区域长度文件的路径。
region_lengths <- read_csv(file = file.path(region_lengths_dir, "gencode.v38.pc_transcripts_region_lengths.csv"), col_names = c("transcript", "UTR5_len", "CDS_len", "UTR3_len")) # this is for human transcriptome, will need to alter if using a different species
#此文件基于人类转录组，如使用其它物种需更换对应文件。

#create themes----
#定义通用绘图主题。
my_theme <- theme_bw()+
  theme(panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank(),
        axis.title = element_text(size = 14),
        axis.text = element_text(size = 16),
        legend.position="none")

#Read in the counts csvs, calculate Counts per Million (CPM) and splice into first and last 25/50nt of CDS/UTRs----
#读取计数 CSV，计算 CPM，并从 UTR/CDS 两端剪切固定长度窗口。
spliced_list <- list()
for (sample in RPF_sample_names) {
  
  #read in counts csv
  #读取单个样本的计数 CSV。
  df <- read_csv(file = file.path(parent_dir, "Counts_files/csv_files", paste0(sample, "_pc_final_counts.csv")))
  
  total_counts <- sum(df$Counts)
  
  df %>%
    mutate(CPM = (Counts / total_counts) * 1000000)  %>%
    inner_join(region_lengths, by = "transcript") -> merged_data
  
  #splice the transcript
  #对转录本进行切片。
  #UTR5 end
  #5'UTR 末端（靠近起始密码子一侧）。
  merged_data %>%
    filter(Position <= UTR5_len) %>%
    group_by(transcript) %>%
    top_n(n = 25, wt = Position) %>% #extracts the 3' most nts
    ungroup() %>%
    mutate(nt = (Position - UTR5_len) - 1) %>%
    group_by(nt) %>%
    summarise(mean_cpm = mean(CPM)) %>%
    ungroup() %>%
    mutate(region = rep("UTR5")) -> UTR5_end
  
  #CDS start
  #CDS 起始区域。
  merged_data %>%
    filter(Position > UTR5_len & Position <= (UTR5_len + CDS_len)) %>%
    mutate(nt = Position - UTR5_len) %>%
    filter(nt <= 50) %>%
    group_by(nt) %>%
    summarise(mean_cpm = mean(CPM)) %>%
    ungroup() %>%
    mutate(region = rep("CDS")) -> CDS_start
  
  #CDS end
  #CDS 末端区域。
  merged_data %>%
    filter(Position > UTR5_len & Position <= (UTR5_len + CDS_len)) %>%
    group_by(transcript) %>%
    top_n(n = 50, wt = Position) %>% #extracts the 3' most nts
    ungroup() %>%
    mutate(nt = (Position - (UTR5_len + CDS_len)) - 1) %>%
    group_by(nt) %>%
    summarise(mean_cpm = mean(CPM)) %>%
    ungroup() %>%
    mutate(region = rep("CDS")) -> CDS_end
  
  #UTR3 start
  #3'UTR 起始区域。
  merged_data %>%
    filter(Position > (UTR5_len + CDS_len)) %>%
    mutate(nt = Position - (UTR5_len + CDS_len)) %>%
    filter(nt <= 25) %>%
    group_by(nt) %>%
    summarise(mean_cpm = mean(CPM)) %>%
    ungroup() %>% 
    mutate(region = rep("UTR3")) -> UTR3_start
  
  bind_rows(UTR5_end, CDS_start, CDS_end, UTR3_start) %>%
    mutate(sample = rep(sample)) -> spliced_list[[sample]]
}

#plot samples individually----
#分别绘制每个样本的单核苷酸 offset 曲线。
for (sample in RPF_sample_names) {
  df <- spliced_list[[sample]]
  
  ylims <- c(0,max(df$mean_cpm))
  
  #5'UTR
  #5'UTR 末端曲线。
  df[df$region == "UTR5" & df$nt < 0,] %>%
    ggplot(aes(x = nt, y = mean_cpm))+
    geom_line(size = 1)+
    ylim(ylims)+
    xlab("nt\n(relative to start codon)")+
    ylab("mean CPM")+
    my_theme -> UTR5_end_plot
  
  #CDS
  #CDS 起始/末端曲线。
  df[df$region == "CDS" & df$nt > 0,] %>%
    ggplot(aes(x = nt, y = mean_cpm))+
    geom_line(size = 1)+
    ylim(ylims)+
    xlab("nt\n(relative to start codon)")+
    my_theme+
    theme(axis.ticks.y = element_blank(),
          axis.text.y = element_blank(),
          axis.title.y = element_blank()) -> CDS_start_plot
  
  df[df$region == "CDS" & df$nt < 0,] %>%
    ggplot(aes(x = nt, y = mean_cpm))+
    geom_line(size = 1)+
    ylim(ylims)+
    xlab("nt\n(relative to stop codon)")+
    my_theme+
    theme(axis.ticks.y = element_blank(),
          axis.text.y = element_blank(),
          axis.title.y = element_blank()) -> CDS_end_plot
  
  #3'UTR
  #3'UTR 起始曲线。
  df[df$region == "UTR3" & df$nt > 0,] %>%
    ggplot(aes(x = nt, y = mean_cpm))+
    geom_line(size = 1)+
    ylim(ylims)+
    xlab("nt\n(relative to stop codon)")+
    my_theme+
    theme(axis.ticks.y = element_blank(),
          axis.text.y = element_blank(),
          axis.title.y = element_blank()) -> UTR3_start_plot
  
  png(filename = file.path(parent_dir, "plots/offset_aligned_single_nt_plots", paste(sample, "offset aligned single nt plot.png")), width = 1300, height = 300)
  grid.arrange(UTR5_end_plot, CDS_start_plot, CDS_end_plot, UTR3_start_plot, nrow = 1, widths = c(1,2,2,1))
  dev.off()
}

#all mean of all samples----
#对所有样本取平均后绘制整体曲线。
do.call("rbind", spliced_list) %>%
  group_by(region, nt) %>%
  summarise(mean_cpm = mean(mean_cpm)) -> all_data

ylims <- c(0,max(all_data$mean_cpm))

#5'UTR
 #5'UTR 末端整体曲线。
all_data[all_data$region == "UTR5" & all_data$nt < 0,] %>%
  ggplot(aes(x = nt, y = mean_cpm))+
  geom_line(size = 1)+
  ylim(ylims)+
  xlab("nt\n(relative to start codon)")+
  ylab("mean CPM")+
  my_theme -> UTR5_end_plot

#CDS
#CDS 起始/末端整体曲线。
all_data[all_data$region == "CDS" & all_data$nt > 0,] %>%
  ggplot(aes(x = nt, y = mean_cpm))+
  geom_line(size = 1)+
  ylim(ylims)+
  xlab("nt\n(relative to start codon)")+
  my_theme+
  theme(axis.ticks.y = element_blank(),
        axis.text.y = element_blank(),
        axis.title.y = element_blank()) -> CDS_start_plot

all_data[all_data$region == "CDS" & all_data$nt < 0,] %>%
  ggplot(aes(x = nt, y = mean_cpm))+
  geom_line(size = 1)+
  ylim(ylims)+
  xlab("nt\n(relative to stop codon)")+
  my_theme+
  theme(axis.ticks.y = element_blank(),
        axis.text.y = element_blank(),
        axis.title.y = element_blank()) -> CDS_end_plot

#3'UTR
#3'UTR 起始整体曲线。
all_data[all_data$region == "UTR3" & all_data$nt > 0,] %>%
  ggplot(aes(x = nt, y = mean_cpm))+
  geom_line(size = 1)+
  ylim(ylims)+
  xlab("nt\n(relative to stop codon)")+
  my_theme+
  theme(axis.ticks.y = element_blank(),
        axis.text.y = element_blank(),
        axis.title.y = element_blank()) -> UTR3_start_plot

png(filename = file.path(parent_dir, "plots/offset_aligned_single_nt_plots/all samples offset aligned single nt plot.png"), width = 1300, height = 300)
grid.arrange(UTR5_end_plot, CDS_start_plot, CDS_end_plot, UTR3_start_plot, nrow = 1, widths = c(1,2,2,1))
dev.off()
