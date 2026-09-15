#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# ANCOM 差异丰度分析驱动（native/main.py 的后端）
#
# 参数经 params.tsv（key<TAB>value 逐行）传入，规避 R 侧引号转义问题。
# 流程：定位 ANCOM 源码 -> feature_table_pre_process 预处理 -> ANCOM 主函数 -> 写结果 CSV。
#
# 用法（一般由 native/main.py analyze 子命令调用）：
#   Rscript run_ancom.R <params.tsv>
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
    stop("用法: Rscript run_ancom.R <params.tsv>")
}
params_file <- args[[1]]

df <- read.delim(params_file, header = FALSE, sep = "\t",
                 stringsAsFactors = FALSE, quote = "", comment.char = "")
params <- stats::setNames(as.list(df$V2), df$V1)
getp <- function(k, default = NULL) {
    v <- params[[k]]
    if (is.null(v) || !nzchar(v)) default else v
}

# ---- 定位 ANCOM 源码 -------------------------------------------------------
ancom_home <- getp("ancom_home")
if (is.null(ancom_home)) ancom_home <- Sys.getenv("ANCOM_HOME", unset = "")
if (!nzchar(ancom_home)) ancom_home <- file.path(Sys.getenv("HOME"), "software", "ANCOM")
ancom_r <- file.path(ancom_home, "programs", "ancom.R")
if (!file.exists(ancom_r)) {
    stop(sprintf(
        "未找到 ANCOM 源码: %s（请设置 --ancom-home 或环境变量 ANCOM_HOME，或运行 native/install.sh）",
        ancom_r))
}

suppressPackageStartupMessages({
    library(nlme)
    library(tidyverse)
    library(compositions)
})
source(ancom_r)

# ---- 读取输入 --------------------------------------------------------------
ft <- read.delim(getp("feature_table"), row.names = 1,
                 check.names = FALSE, stringsAsFactors = FALSE)
ft[] <- lapply(ft, as.numeric)

md <- read.delim(getp("metadata"), check.names = FALSE, stringsAsFactors = FALSE)

sample_var   <- getp("sample_var")
main_var     <- getp("main_var")
group_var    <- getp("group_var")
out_cut      <- as.numeric(getp("out_cut", "0.05"))
zero_cut     <- as.numeric(getp("zero_cut", "0.9"))
lib_cut      <- as.numeric(getp("lib_cut", "0"))
neg_lb       <- as.logical(getp("neg_lb", "FALSE"))
p_adj_method <- getp("p_adj_method", "BH")
alpha        <- as.numeric(getp("alpha", "0.05"))
adj_formula  <- getp("adj_formula")
rand_formula <- getp("rand_formula")

# ---- ANCOM 分析 ------------------------------------------------------------
prepro <- feature_table_pre_process(ft, md, sample_var, group_var,
                                    out_cut, zero_cut, lib_cut, neg_lb)
res <- ANCOM(prepro$feature_table, prepro$meta_data, prepro$structure_zeros,
             main_var, p_adj_method, alpha, adj_formula, rand_formula, NULL)

write.csv(res$out, getp("output"), row.names = FALSE)
cat("ANCOM_OK\n")
