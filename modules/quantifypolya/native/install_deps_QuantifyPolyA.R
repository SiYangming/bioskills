#!/usr/bin/env Rscript
# =============================================================================
# install_deps_QuantifyPolyA.R — QuantifyPolyA（R 包）依赖安装配方
#
# 归属    ：bioskills modules/quantifypolya/native/install_deps_QuantifyPolyA.R
# 来源    ：仓库根目录遗留安装辅助脚本迁移（2021-06 随本地下载包配套使用，
#           记录了 QuantifyPolyA 0.3.0 的完整 CRAN + Bioconductor 依赖路线）。
#           原脚本含 R<3.5 时代的 BiocInstaller::biocLite 分支（已废弃，移除，
#           历史说明见下）；本迁移版把两处「install.packages('./*.tar.gz')」
#           本地包引用改造为「优先本地路径参数、缺失时自动从官方 URL 下载」，
#           使大包文件从仓库删除后仍可一键重建。
#
# 版本    ：QuantifyPolyA 0.3.0（sourceforge 最新版，2021-06-22 发布）；
#           ggalt 0.4.0（CRAN 已归档，唯一不在 CRAN 主源/需特殊拉取的依赖）
# 依赖路线（按 DESCRIPTION Depends + 原脚本整理）：
#   CRAN        : bedr stringr outliers dplyr tidyr matrixStats pbmcapply
#                 FactoMineR factoextra proj4 ash plotly ggplot2 uwot
#   CRAN-Archive: ggalt（0.4.0，2021-06 起 CRAN 归档；conda-forge 亦有 r-ggalt）
#   Bioconductor: GenomicRanges GenomicFeatures rtracklayer Rsamtools DESeq2
#                 ggbio（BiocManager 自动匹配当前 Bioc 版本）
#   R 版本      ：需 R >= 3.5（现代依赖随 BiocManager 解析）；建议 R >= 4.0，
#                 推荐 4.2+（原包 2021-06 打包于 R 4.1 时代）
#
# 用法：
#   Rscript install_deps_QuantifyPolyA.R                     # 全自动（在线下载缺失包）
#   Rscript install_deps_QuantifyPolyA.R /path/to/QuantifyPolyA_0.3.0.tar.gz
#     # 指定本地 QuantifyPolyA 源码包（跳过 sourceforge 下载，离线可装）
#   Rscript install_deps_QuantifyPolyA.R <qpa.tar.gz> <ggalt_0.4.0.tar.gz>
#     # 两个本地包都指定（完全离线）
#   环境变量 QUANTIFYPOLYA_VERSION 可覆盖默认 0.3.0（URL 模板同步替换，
#   一般无需设置）。
#
# 完成后 library(QuantifyPolyA) 即可使用；分析驱动见 native/main.py quant /
# native/run_quantifypolya.R。
# =============================================================================
options(repos = c(CRAN = "https://cloud.r-project.org"))
options(timeout = 600)  # sourceforge / CRAN Archive 大文件下载放宽超时

args <- commandArgs(trailingOnly = TRUE)
QPA_TGZ  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else ""
GGALT_TGZ <- if (length(args) >= 2 && nzchar(args[2])) args[2] else ""

QPA_VERSION <- Sys.getenv("QUANTIFYPOLYA_VERSION", unset = "0.3.0")
GGALT_VERSION <- "0.4.0"

CRAN_DEPS <- c("bedr", "stringr", "outliers", "dplyr", "tidyr", "matrixStats",
               "pbmcapply", "FactoMineR", "factoextra", "proj4", "ash",
               "plotly", "ggplot2", "uwot")
BIOC_DEPS <- c("GenomicRanges", "GenomicFeatures", "rtracklayer", "Rsamtools",
               "DESeq2", "ggbio")

## ---- 辅助 ---------------------------------------------------------------
need <- function(pkg) !requireNamespace(pkg, quietly = TRUE)
logi <- function(...) cat(sprintf("[install_deps]", ...), "\n")

install_cran <- function(pkg) {
  if (need(pkg)) {
    logi("CRAN 安装 %s ...", pkg)
    install.packages(pkg)
  } else {
    logi("%s 已安装，跳过", pkg)
  }
}

install_bioc <- function(pkg) {
  if (need(pkg)) {
    logi("Bioconductor 安装 %s ...", pkg)
    BiocManager::install(pkg, update = FALSE, ask = FALSE)
  } else {
    logi("%s 已安装，跳过", pkg)
  }
}

# 优先使用本地源码包（离线可装）；缺失时下载官方 tar.gz 到临时目录后本地源码安装
install_tar_gz <- function(url, local_tar, label) {
  if (nzchar(local_tar) && file.exists(local_tar)) {
    logi("使用本地包安装 %s: %s", label, local_tar)
    install.packages(local_tar, repos = NULL, type = "source")
    return(invisible(TRUE))
  }
  dest <- tempfile(fileext = ".tar.gz")
  logi("下载 %s: %s", label, url)
  ok <- tryCatch({
    download.file(url, dest, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok || !file.exists(dest) || file.info(dest)$size < 1000) {
    unlink(dest)
    stop(sprintf("自动下载 %s 失败（网络受限时请手动下载后作为参数传入）：\n  %s\n  Rscript %s <本地包路径>",
                 label, url, sub("^--file=", "", commandArgs()[1])), call. = FALSE)
  }
  install.packages(dest, repos = NULL, type = "source")
  unlink(dest)
}

## ---- BiocManager 就绪 ----------------------------------------------------
if (need("BiocManager")) install_cran("BiocManager")

## ---- 1) CRAN 依赖 --------------------------------------------------------
logi("阶段 1/4：CRAN 依赖（共 %d 个）", length(CRAN_DEPS))
for (p in CRAN_DEPS) install_cran(p)

## ---- 2) ggalt（CRAN 归档，需 Archive / conda-forge）-----------------------
logi("阶段 2/4：ggalt %s（CRAN 已归档，唯一需特殊拉取的依赖）", GGALT_VERSION)
if (need("ggalt")) {
  ggalt_url <- sprintf("https://cran.r-project.org/src/contrib/Archive/ggalt/ggalt_%s.tar.gz",
                       GGALT_VERSION)
  install_tar_gz(ggalt_url, GGALT_TGZ, "ggalt")
}

## ---- 3) Bioconductor 依赖 -------------------------------------------------
logi("阶段 3/4：Bioconductor 依赖（共 %d 个，BiocManager 自动匹配版本）", length(BIOC_DEPS))
for (p in BIOC_DEPS) install_bioc(p)

## ---- 4) QuantifyPolyA 本体（0.3.0，sourceforge 最新版）--------------------
logi("阶段 4/4：QuantifyPolyA %s 本体", QPA_VERSION)
if (need("QuantifyPolyA")) {
  qpa_url <- sprintf("https://downloads.sourceforge.net/project/quantifypoly-a/QuantifyPolyA_%s.tar.gz",
                     QPA_VERSION)
  # sourceforge 下载可能受网络/镜像限制：downloads.sourceforge.net 直连不可用时，
  # 脚本会报错并提示改用 https://sourceforge.net/projects/quantifypoly-a/files/ 的
  # /download 入口手动下载后传入本地路径。
  install_tar_gz(qpa_url, QPA_TGZ, "QuantifyPolyA")
}

## ---- 断言 ----------------------------------------------------------------
if (!requireNamespace("QuantifyPolyA", quietly = TRUE))
  stop("QuantifyPolyA 安装失败：library() 不可用", call. = FALSE)
ver <- as.character(packageVersion("QuantifyPolyA"))
cat(sprintf("[install_deps] QuantifyPolyA %s 安装成功，依赖就绪。\n", ver))
logi("library(QuantifyPolyA) 即可使用；分析驱动：python native/main.py quant ...")
