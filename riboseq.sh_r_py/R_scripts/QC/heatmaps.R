#load libraries
#加载库。
library(tidyverse)
library(grid)
library(gridExtra)
library(parallel)
library(viridis)

#read in common variables
#读取通用变量。
source("common_variables.R")

#functions
#函数定义。
#write a function that will read in a csv file for use with parLapply
#定义用于 parLapply 并行读取 CSV 的函数。
read_counts_csv <- function(k){
  df <- read.csv(file = k)
  df$fyle <- rep(k)
  return(df)
}

#exports just the legend of a plot
#提取 ggplot 图中的图例对象。
myLegend <- function(a.gplot){
  tmp <- ggplot_gtable(ggplot_build(a.gplot))
  leg <- which(sapply(tmp$grobs, function(x) x$name) == "guide-box")
  legend <- tmp$grobs[[leg]]
  return(legend)}

#themes
#定义通用绘图主题。
myTheme <- theme_classic()+
  theme(axis.title = element_text(size = 16),
        axis.text = element_text(size = 16),
        legend.position = "none")

#read in data----
#读取数据。
#generate a list of file names
#生成各样本、各 read length、各剪切区域对应的文件名列表。
fyle_list <- list()
for(sample in RPF_sample_names) {
  for(i in lengths){
    fyle_list[[paste(sample, i, "start", sep = "_")]] <- file.path(parent_dir, "Analysis/spliced_counts", paste0(sample, "_pc_L", i, "_Off0_start_site.csv"))
    fyle_list[[paste(sample, i, "stop", sep = "_")]] <- file.path(parent_dir, "Analysis/spliced_counts", paste0(sample, "_pc_L", i, "_Off0_stop_site.csv"))
    fyle_list[[paste(sample, i, "UTR5_start", sep = "_")]] <- file.path(parent_dir, "Analysis/spliced_counts", paste0(sample, "_pc_L", i, "_Off0_UTR5_start.csv"))
    fyle_list[[paste(sample, i, "UTR3_end", sep = "_")]] <- file.path(parent_dir, "Analysis/spliced_counts", paste0(sample, "_pc_L", i, "_Off0_UTR3_end.csv"))
  }
}

#read in the data with parLapply
#使用 parLapply 并行读取数据。
no_cores <- detectCores() - 1 #sets the number of cores to use (all but one)
#设置使用的核心数（保留一个核心）。
cl <- makeCluster(no_cores) #Initiates cluster
#初始化集群。
data_list <- parLapply(cl, fyle_list, read_counts_csv) #reads in the data
#并行读取所有文件。
stopCluster(cl) #Stops cluster
#停止集群。

#combine data_list into one data frame
#将所有列表元素合并为一个数据框。
all_data <- do.call("rbind", data_list)

#extract sample, read length and splice position from fylenames
#从文件名中提取样本名、读长和剪切位置标记。
all_data %>%
  mutate(read_length = str_remove(fyle, ".+pc_L"),
         read_length = as.numeric(str_remove(read_length, "_Off0_.+")),
         sample = str_remove(fyle, ".+spliced_counts/"),
         sample = factor(str_remove(sample, "_pc.+")),
         splice = str_remove(fyle, ".+Off0_"),
         splice = factor(str_remove(splice, ".csv"))) %>%
  select(-fyle) -> all_data

summary(all_data)

#plot heatmaps----
#绘制不同剪切位置和读长的热图。
for (sample in RPF_sample_names) {
  
  fill_lims <- c(0, max(all_data$counts[all_data$sample == sample]))
  
  all_data[all_data$sample == sample & all_data$splice == "start_site",] %>%
    ggplot(aes(x = position, y = read_length, fill= counts)) + 
    geom_tile()+
    scale_fill_viridis(discrete = F, limits = fill_lims)+
    xlab("Position relative to start codon")+
    ylab("Read length")+
    myTheme -> start_site_plot
  
  all_data[all_data$sample == sample & all_data$splice == "stop_site",] %>%
    ggplot(aes(x = position, y = read_length, fill= counts)) + 
    geom_tile()+
    scale_fill_viridis(discrete = F, limits = fill_lims)+
    xlab("Position relative to stop codon")+
    ylab("Read length")+
    myTheme -> stop_site_plot
  
  all_data[all_data$sample == sample & all_data$splice == "UTR5_start",] %>%
    ggplot(aes(x = position, y = read_length, fill= counts)) + 
    geom_tile()+
    scale_fill_viridis(discrete = F, limits = fill_lims)+
    xlab("Position relative to 5\' end of transcript")+
    ylab("Read length")+
    myTheme -> UTR5_start_plot
  
  all_data[all_data$sample == sample & all_data$splice == "UTR3_end",] %>%
    mutate(position = position - 50) %>%
    ggplot(aes(x = position, y = read_length, fill= counts)) + 
    geom_tile()+
    scale_fill_viridis(discrete = F, limits = fill_lims)+
    xlab("Position relative to 3\' end of transcript")+
    ylab("Read length")+
    myTheme -> UTR3_end_plot
  
  all_data %>%
    ggplot(aes(x = position, y = read_length, fill= counts)) + 
    geom_tile()+
    scale_fill_viridis(discrete = F, limits = fill_lims)+
    theme(legend.text = element_text(size = 16),
          legend.title = element_text(size = 16)) -> legend_plot
  
  legend <- myLegend(legend_plot)
  
  png(filename = file.path(parent_dir, paste0("plots/heatmaps/", sample, "_heatmap.png")), width = 2000, height = 300)
  grid.arrange(UTR5_start_plot, start_site_plot, stop_site_plot, UTR3_end_plot, legend,
               widths = c(1,2,2,1, 0.2))
  dev.off()
}
