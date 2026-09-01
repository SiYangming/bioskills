#load libraries----
# 加载所需 R 包。----
library(rrvgo)
library(tidyverse)

#read in common variables----
#读取通用变量。
source("common_variables.R")

#set threshold----
#设置相似性阈值。
#This determines how many parent terms will be defined when reducing the GO terms
#scale of 0.1-0.9 with 0.9 have the the most reduction or lowest amount of parent terms. 0.7 is the standard analysis
#该阈值决定在合并 GO 术语时保留多少“父”术语，范围 0.1–0.9，0.9 表示压缩最强（父术语数量最少），通常使用 0.7。
threshold <- 0.7

#set adjusted p-value threshold----
#设置校正后 p 值阈值。
#This determines which GO terms are deemed statistically significant
#该阈值用于定义哪些 GO 术语在统计学上显著。
padj_threshold <- 0.05

#read in data----
##GO term IDs----
#读取 GO 术语与 ID 的映射表。
gsea_dir <- "path/to/dir"
GO_terms <- read.table(file.path(gsea_dir, "go_term_to_id.tsv"), header = T)

#subset GO_terms for the ontology
#按本体类型将 GO 术语划分为 BP、CC、MF。
GO_terms %>%
  filter(str_detect(pathway, "GOBP")) -> BP_GO_terms
GO_terms %>%
  filter(str_detect(pathway, "GOCC")) -> CC_GO_terms
GO_terms %>%
  filter(str_detect(pathway, "GOMF")) -> MF_GO_terms

##FGSEA results----
#读取 FGSEA 的分析结果。
load(file.path(parent_dir, "Analysis/fgsea/bio_processes_results.Rdata"))
load(file.path(parent_dir, "Analysis/fgsea/cell_comp_results.Rdata"))
load(file.path(parent_dir, "Analysis/fgsea/mol_funs_results.Rdata"))

#extract the TE output as a dataframe (this is the 3rd item in the fgsea results list, can change to RPFs [[1]] or Totals [[2]] if required)
#提取 TE 结果（列表中的第 3 个元素）为数据框，如需分析 RPFs 或 Totals，可改用 [[1]] 或 [[2]]。
BP_df <- as.data.frame(bio_processes_results[[3]])
CC_df <- as.data.frame(cell_comp_results[[3]])
MF_df <- as.data.frame(mol_funs_results[[3]])

#merge and filter data----
#合并 FGSEA 结果与 GO 术语信息，并筛选显著的条目。
#merge fgsea data with GO terms, select GO_ID, adjusted p-value and NES columns and filter for significant adjusted p-values
BP_GO_terms %>%
  inner_join(BP_df, by = "pathway") %>%
  select(GO_ID, padj, NES) %>%
  filter(padj < padj_threshold) -> BP_data

CC_GO_terms %>%
  inner_join(CC_df, by = "pathway") %>%
  select(GO_ID, padj, NES) %>%
  filter(padj < padj_threshold) -> CC_data

MF_GO_terms %>%
  inner_join(MF_df, by = "pathway") %>%
  select(GO_ID, padj, NES) %>%
  filter(padj < padj_threshold) -> MF_data

#subset into up and down
#根据 NES 将通路划分为上调和下调。
BP_data %>%
  filter(NES > 0) -> BP_up

BP_data %>%
  filter(NES < 0) -> BP_down

CC_data %>%
  filter(NES > 0) -> CC_up

CC_data %>%
  filter(NES < 0) -> CC_down

MF_data %>%
  filter(NES > 0) -> MF_up

MF_data %>%
  filter(NES < 0) -> MF_down

#make sim matrices----
#基于 GO ID 构建相似性矩阵。
BP_simMatrix_up <- calculateSimMatrix(BP_up$GO_ID,
                                      orgdb="org.Mm.eg.db",
                                      ont="BP",
                                      method="Rel")

BP_simMatrix_down <- calculateSimMatrix(BP_down$GO_ID,
                                        orgdb="org.Mm.eg.db",
                                        ont="BP",
                                        method="Rel")

CC_simMatrix_up <- calculateSimMatrix(CC_up$GO_ID,
                                      orgdb="org.Mm.eg.db",
                                      ont="CC",
                                      method="Rel")

CC_simMatrix_down <- calculateSimMatrix(CC_down$GO_ID,
                                        orgdb="org.Mm.eg.db",
                                        ont="CC",
                                        method="Rel")

MF_simMatrix_up <- calculateSimMatrix(MF_up$GO_ID,
                                      orgdb="org.Mm.eg.db",
                                      ont="MF",
                                      method="Rel")

MF_simMatrix_down <- calculateSimMatrix(MF_down$GO_ID,
                                        orgdb="org.Mm.eg.db",
                                        ont="MF",
                                        method="Rel")

#create scores----
#为每个 GO 术语生成分数（-log10(padj)）。
BP_scores_up <- setNames(-log10(BP_up$padj), BP_up$GO_ID)
BP_scores_down <- setNames(-log10(BP_down$padj), BP_down$GO_ID)

CC_scores_up <- setNames(-log10(CC_up$padj), CC_up$GO_ID)
CC_scores_down <- setNames(-log10(CC_down$padj), CC_down$GO_ID)

MF_scores_up <- setNames(-log10(MF_up$padj), MF_up$GO_ID)
MF_scores_down <- setNames(-log10(MF_down$padj), MF_down$GO_ID)

#determine reduced GO terms
#在给定相似性阈值下合并 GO 术语，得到精简后的父术语集合。
BP_reducedTerms_up <- reduceSimMatrix(BP_simMatrix_up,
                                      BP_scores_up,
                                      threshold=threshold,
                                      orgdb="org.Mm.eg.db")

BP_reducedTerms_down <- reduceSimMatrix(BP_simMatrix_down,
                                        BP_scores_down,
                                        threshold=threshold,
                                        orgdb="org.Mm.eg.db")

CC_reducedTerms_up <- reduceSimMatrix(CC_simMatrix_up,
                                      CC_scores_up,
                                      threshold=threshold,
                                      orgdb="org.Mm.eg.db")

CC_reducedTerms_down <- reduceSimMatrix(CC_simMatrix_down,
                                        CC_scores_down,
                                        threshold=threshold,
                                        orgdb="org.Mm.eg.db")

MF_reducedTerms_up <- reduceSimMatrix(MF_simMatrix_up,
                                      MF_scores_up,
                                      threshold=threshold,
                                      orgdb="org.Mm.eg.db")

MF_reducedTerms_down <- reduceSimMatrix(MF_simMatrix_down,
                                        MF_scores_down,
                                        threshold=threshold,
                                        orgdb="org.Mm.eg.db")

#write out reduced terms----
#将精简后的 GO 术语结果写出为 CSV。
write_csv(BP_reducedTerms_up, file = file.path(parent_dir, "Analysis/fgsea/bio_processes_reducedTerms_up.csv"))
write_csv(BP_reducedTerms_down, file = file.path(parent_dir, "Analysis/fgsea/bio_processes_reducedTerms_down.csv"))

write_csv(CC_reducedTerms_up, file = file.path(parent_dir, "Analysis/fgsea/cell_comp_reducedTerms_up.csv"))
write_csv(CC_reducedTerms_down, file = file.path(parent_dir, "Analysis/fgsea/cell_comp_reducedTerms_down.csv"))

write_csv(MF_reducedTerms_up, file = file.path(parent_dir, "Analysis/fgsea/mol_funs_reducedTerms_up.csv"))
write_csv(MF_reducedTerms_down, file = file.path(parent_dir, "Analysis/fgsea/mol_funs_reducedTerms_down.csv"))

#plot treemaps----
#绘制 treemap，可视化每个父术语的富集程度和层级结构。
png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/bio_processes_up_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(BP_reducedTerms_up, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/bio_processes_down_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(BP_reducedTerms_down, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/cell_comp_up_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(CC_reducedTerms_up, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/cell_comp_down_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(CC_reducedTerms_down, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/mol_funs_up_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(MF_reducedTerms_up, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/mol_funs_down_treemap.png"), width = 500, height =500 )
treemap <- treemapPlot(MF_reducedTerms_down, size = "score") #size gives size of GO term, score is according to the score you define (pval)
dev.off()

#make bar charts----
#绘制精简后父术语的条形图。
#BP
BP_reducedTerms_down %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() %>%
  mutate(score = -score) -> BP_reducedTerms_down_summarised

BP_reducedTerms_up %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() -> BP_reducedTerms_up_summarised

BP_reducedTerms_down_summarised %>%
  bind_rows(BP_reducedTerms_up_summarised) -> BP_reducedTerms_summarised

BP_reducedTerms_summarised %>%
  arrange(score) %>%
  pull(parentTerm) -> order_BP_terms

BP_reducedTerms_summarised%>%
  ggplot(aes(x = factor(parentTerm, levels = order_BP_terms, ordered = T), y = score))+
  geom_col()+
  coord_flip()+
  theme_classic()+
  theme(axis.title = element_blank())+
  ggtitle("Enriched Biological Processes", subtitle = "parent terms summarised") -> BP_summarised_terms_plot

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/bio_processes_summarised_terms_plot.png"), width = 450, height =350 )
print(BP_summarised_terms_plot)
dev.off()

#CC
CC_reducedTerms_down %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() %>%
  mutate(score = -score) -> CC_reducedTerms_down_summarised

CC_reducedTerms_up %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() -> CC_reducedTerms_up_summarised

CC_reducedTerms_down_summarised %>%
  bind_rows(CC_reducedTerms_up_summarised) -> CC_reducedTerms_summarised

CC_reducedTerms_summarised %>%
  arrange(score) %>%
  pull(parentTerm) -> order_CC_terms

CC_reducedTerms_summarised%>%
  ggplot(aes(x = factor(parentTerm, levels = order_CC_terms, ordered = T), y = score))+
  geom_col()+
  coord_flip()+
  theme_classic()+
  theme(axis.title = element_blank())+
  ggtitle("Enriched Cellular Components", subtitle = "parent terms summarised") -> CC_summarised_terms_plot

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/cell_comp_summarised_terms_plot.png"), width = 450, height =350 )
print(CC_summarised_terms_plot)
dev.off()

#MF
MF_reducedTerms_down %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() %>%
  mutate(score = -score) -> MF_reducedTerms_down_summarised

MF_reducedTerms_up %>%
  group_by(parentTerm) %>%
  summarise(score = mean(score)) %>%
  ungroup() -> MF_reducedTerms_up_summarised

MF_reducedTerms_down_summarised %>%
  bind_rows(MF_reducedTerms_up_summarised) -> MF_reducedTerms_summarised

MF_reducedTerms_summarised %>%
  arrange(score) %>%
  pull(parentTerm) -> order_MF_terms

MF_reducedTerms_summarised%>%
  ggplot(aes(x = factor(parentTerm, levels = order_MF_terms, ordered = T), y = score))+
  geom_col()+
  coord_flip()+
  theme_classic()+
  theme(axis.title = element_blank())+
  ggtitle("Enriched Molecular Functions", subtitle = "parent terms summarised") -> MF_summarised_terms_plot

png(filename = file.path(parent_dir, "plots/fgsea/rrvgo/mol_funs_summarised_terms_plot.png"), width = 450, height =350 )
print(MF_summarised_terms_plot)
dev.off()
