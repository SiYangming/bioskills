#!/usr/bin/env Rscript
# =============================================================================
# run_matrixeqtl.R — Matrix eQTL 统一分析驱动（单一文件，双模式）
#
# 来源整合：本文件由两脚本合并而来——
#   1) run_matrixeqtl.R（原模块精简驱动）：`Rscript run_matrixeqtl.R <params.tsv>`
#      键<TAB>值 两列，供 native/main.py analyze 子命令调用；
#   2) run_Matrix_eQTL_for_M1.R（独立 CLI / M1 Mac 调优）：`Rscript run_matrixeqtl.R --SNP_file ...`
#      保留其全功能参数、文件/权限预检、BLAS/核心数/线程环境调优与 cis+trans 双输出
#      （--output-prefix 时产出 <prefix>_eQTL_trans.txt / <prefix>_eQTL_cis.txt）。
#   依赖仅 base R + MatrixEQTL（核心数探测用 R 自带 parallel 推荐包；不再需要 optparse/data.table）。
#
# 用法一（params.tsv，main.py 用；无 `--` 开头即进入本模式）：
#   Rscript run_matrixeqtl.R <params.tsv>
#   params.tsv 键：snps gene [covariates] output model pv_threshold pv_threshold_cis
#                  cis_dist snpspos genepos slice_size threads pvalue_hist verbose
#
# 用法二（独立 CLI，M1/服务器直接跑；参数名大小写与 -/_ 均可，如 --SNP_file=--SNP-file）：
#   Rscript run_matrixeqtl.R --SNP-file snps.txt --exp-file ge.txt \
#       [--covariates-file covariates.txt] [--snps-loc snpspos.txt --gene-loc genepos.txt] \
#       [--output-prefix eqtl | --output result.txt] \
#       [--trans-p 1e-5] [--cis-p 0] [--model linear] [--slice-size 3000] \
#       [--cis-dist 1000000] [--threads auto] [--pvalue-hist FALSE] [--verbose TRUE]
#   - 提供 --output-prefix：trans → <prefix>_eQTL_trans.txt；--cis-p>0 时另写 <prefix>_eQTL_cis.txt
#   - 提供 --output：trans → 该文件；--cis-p>0 时另写 <output>.cis
#   - --cis-p>0 时 --snps-loc/--gene-loc 必填（cis 分区）
#   - covariates 文件允许为空（等价无协变量）；缺失亦等价无协变量
#
# 完成时打印 "RMATRIXEQTL_OK output=<trans>"（cis 启用另打印 RMATRIXEQTL_OK_CIS）。
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)

print_usage <- function(con = stdout()) {
  cat('run_matrixeqtl.R — Matrix eQTL 分析驱动（params.tsv / 独立 CLI 双模式）\n',
      '用法:  Rscript run_matrixeqtl.R <params.tsv>\n',
      '        Rscript run_matrixeqtl.R --SNP-file snps.txt --exp-file ge.txt [选项]\n',
      '关键参数（长名不区分大小写，- 与 _ 等价）:\n',
      '  --SNP-file <f> 基因型矩阵      --exp-file <f> 表达矩阵（样本列需与前者一致）\n',
      '  --covariates-file <f> 协变量（可空/可缺）  --output-prefix <p> | --output <f>\n',
      '  --snps-loc <f> --gene-loc <f>（cis 分区必需）  --cis-dist <bp> 默认 1e6\n',
      '  --trans-p <t> 默认 1e-5   --cis-p <t> 默认 0（>0 启用 cis）\n',
      '  --model linear|anova|linear_cross 默认 linear\n',
      '  --slice-size 默认 2000    --threads auto|N    --pvalue-hist TRUE|FALSE(默认)\n',
      sep = "")
}

if (length(args) >= 1 && any(grepl("^-", args))) {
  cli_mode <- TRUE
} else if (length(args) == 1) {
  cli_mode <- FALSE
} else {
  print_usage(con = stderr())
  stop("用法错误：请提供 <params.tsv> 或一组 --key value 参数（--help/-h 查看更多）", call. = FALSE)
}

if (any(args %in% c("-h", "--help"))) {
  print_usage()
  quit(save = "no", status = 0)
}

## ---- 键名归一化：统一转小写并去掉 -/_，便于兼容两种命名习惯 ----
norm_key <- function(k) gsub("[-_]", "", tolower(k))

KEY_ALIAS <- c(
  snps        = "snps",        snpfile     = "snps",      snpsfile    = "snps",
  gene        = "gene",        expfile     = "gene",       expression = "gene",
  covariates  = "covariates",  covariatesfile = "covariates",
  snpspos     = "snpspos",     snpsloc     = "snpspos",
  genepos     = "genepos",     geneloc     = "genepos",
  output      = "output",      outputprefix = "output_prefix",
  model       = "model",
  pvthreshold = "pv_threshold", trans_p = "pv_threshold", transp = "pv_threshold",
  pvthresholdcis = "pv_threshold_cis", cis_p = "pv_threshold_cis", cisp = "pv_threshold_cis",
  cisdist     = "cis_dist",    cis_dist    = "cis_dist",
  slicesize   = "slice_size",  slice_size  = "slice_size",
  threads     = "threads",
  pvaluehist  = "pvalue_hist",
  verbose     = "verbose"
)

## ---- 参数装载：params.tsv（键<TAB>值）或 CLI --key value / --key=value ----
read_params_file <- function(f) {
  par <- read.delim(f, header = FALSE, sep = "\t",
                    stringsAsFactors = FALSE, quote = "")
  p <- as.list(par$V2)
  names(p) <- par$V1
  p
}

parse_cli <- function(raw) {
  p <- list()
  i <- 1L
  while (i <= length(raw)) {
    tok <- raw[i]
    if (grepl("^--", tok)) {
      kv <- sub("^--", "", tok)
      if (grepl("=", kv, fixed = TRUE)) {
        sp <- strsplit(kv, "=", fixed = TRUE)[[1]]
        key <- sp[1]; val <- sp[2]
      } else {
        key <- kv
        if (i + 1L > length(raw)) stop("缺少参数值: --", kv, call. = FALSE)
        val <- raw[i + 1L]; i <- i + 1L
      }
      nk <- norm_key(key)
      if (!(nk %in% names(KEY_ALIAS))) stop("未知参数: --", key, "（--help 查看支持参数）", call. = FALSE)
      p[[KEY_ALIAS[[nk]]]] <- val
    } else {
      stop("无法识别参数: ", tok, "（CLI 模式参数需以 -- 开头）", call. = FALSE)
    }
    i <- i + 1L
  }
  p
}

p <- if (!cli_mode) read_params_file(args[1]) else parse_cli(args)

## ---- 取值辅助 ----
raw <- function(k) p[[k]]
num <- function(k, d) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.numeric(v) }
intv <- function(k, d) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.integer(v) }
chr <- function(k, d = NULL) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.character(v) }
bool <- function(k, d) {
  v <- raw(k)
  if (is.null(v) || is.na(v) || v == "") return(d)
  tolower(v) %in% c("true", "1", "yes", "t")
}

## ---- 硬件 / 线程调优（吸收自 M1 脚本；依赖仅 base R 自带 parallel） ----
auto_cores <- function() {
  nc <- tryCatch(parallel::detectCores(logical = FALSE),
                 error = function(e) NA_integer_)
  if (is.na(nc) || nc < 1) nc <- tryCatch(parallel::detectCores(), error = function(e) 4L)
  if (is.na(nc) || nc < 1) nc <- 4L
  max(1L, nc - 1L)
}

thr_raw <- chr("threads", "auto")
threads <- if (tolower(thr_raw) == "auto") auto_cores() else max(1L, intv("threads", 4L))

## BLAS 检查（提示性；仅 Accelerate/RhpcBLASctl 可控时才做实际设置）
blas <- tryCatch(sessionInfo()$BLAS, error = function(e) "unknown")
if (length(blas) && !is.na(blas) && !grepl("Accelerate", blas)) {
  message("[提示] 当前 BLAS: ", blas, "；如用 macOS M 系列可考虑 Apple Accelerate 或 ARM OpenBLAS 提升性能")
}

## OpenBLAS / 多线程 BLAS 线程生效机制（参数 threads）
# 1) 解析在 auto_cores()/intv() 完成（上方）；此处直接消费 `threads`。
# 2) Matrix_eQTL_main 是纯 R 大矩阵运算，加速来自 R 底层多线程 BLAS（OpenBLAS /
#    Apple Accelerate / MKL）。四组环境变量须在首次矩阵运算（即 library(MatrixEQTL)
#    之后真正调用前）已设置 —— 本脚本在加载包之前即 Sys.setenv，保证生效。
# 3) RhpcBLASctl（若已安装）可在运行期直接改当前进程 BLAS 线程，属额外细化；
#    未安装时静默跳过，仅依赖第 2 步的环境变量。
Sys.setenv(
  OMP_NUM_THREADS          = as.character(threads),
  OPENBLAS_NUM_THREADS     = as.character(threads),
  VECLIB_MAXIMUM_THREADS   = as.character(threads),
  MKL_NUM_THREADS          = as.character(threads)
)
if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
  tryCatch(RhpcBLASctl::blas_set_num_threads(threads),
           error = function(e) NULL)
}

## MatrixEQTL 内存选项（大矩阵下避免保留 gene 对象副本）
options(MatrixEQTL.dont.preserve.gene.object = TRUE)

## ---- 必填与文件预检 ----
check_readable <- function(f, what) {
  if (is.null(f) || !nzchar(f)) stop("缺少必填文件参数: ", what, call. = FALSE)
  if (!file.exists(f)) stop("文件不存在: ", what, " = ", f, call. = FALSE)
  if (file.access(f, mode = 4) != 0) stop("无读取权限: ", what, " = ", f, call. = FALSE)
}

snps_f <- chr("snps", stop("缺少 snps"))
gene_f <- chr("gene", stop("缺少 gene"))
check_readable(snps_f, "snps")
check_readable(gene_f, "gene")

cov_f <- chr("covariates")
has_cov <- FALSE
if (!is.null(cov_f)) {
  check_readable(cov_f, "covariates")
  if (file.size(cov_f) > 0) {
    has_cov <- TRUE
  } else {
    message("[提示] covariates 文件为空，等价无协变量")
  }
}

model_name <- tolower(chr("model", "linear"))
if (!(model_name %in% c("linear", "anova", "linear_cross")))
  stop("model 必须是 linear | anova | linear_cross", call. = FALSE)
if (model_name == "linear_cross" && !has_cov)
  stop("model=linear_cross 需要 covariates（当前无协变量）", call. = FALSE)

pv_threshold     <- num("pv_threshold", 1e-5)
pv_threshold_cis <- num("pv_threshold_cis", 0)
cis_dist         <- intv("cis_dist", 1000000L)
slice_size       <- intv("slice_size", 2000L)
pvalue_hist      <- bool("pvalue_hist", FALSE)
verbose          <- bool("verbose", TRUE)

## ---- 输出路径解析：--output-prefix（M1 命名）或 --output（模块命名）----
prefix <- chr("output_prefix")
out_f  <- chr("output")
if (is.null(prefix) && is.null(out_f))
  stop("需要输出：--output-prefix <p> 或 --output <f>（--help 查看）", call. = FALSE)
if (!is.null(prefix) && !is.null(out_f))
  message("[提示] 同时给了 output-prefix 与 output，按 output-prefix 处理")

if (!is.null(prefix)) {
  trans_file <- paste0(prefix, "_eQTL_trans.txt")
  cis_file   <- if (pv_threshold_cis > 0) paste0(prefix, "_eQTL_cis.txt") else ""
} else {
  trans_file <- out_f
  cis_file   <- if (pv_threshold_cis > 0) paste0(out_f, ".cis") else ""
}

## 输出目录预检（相对路径 "." 视为存在）
for (f in c(trans_file, cis_file)) {
  if (!nzchar(f)) next
  d <- dirname(f)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (file.access(d, mode = 2) != 0) stop("输出目录不可写: ", d, call. = FALSE)
}

## ---- 位置表（仅 cis 分区需要） ----
snpspos <- NULL; genepos <- NULL
if (pv_threshold_cis > 0) {
  sp_f <- chr("snpspos"); gp_f <- chr("genepos")
  if (is.null(sp_f) || is.null(gp_f))
    stop("pv_threshold_cis>0 时必须提供 snpspos 与 genepos（--snps-loc/--gene-loc）", call. = FALSE)
  check_readable(sp_f, "snpspos"); check_readable(gp_f, "genepos")
  snpspos <- read.table(sp_f, header = TRUE, stringsAsFactors = FALSE)
  genepos <- read.table(gp_f, header = TRUE, stringsAsFactors = FALSE)
  snpspos$chr <- as.character(snpspos$chr)
  genepos$chr <- as.character(genepos$chr)
}

## ---- MatrixEQTL 加载与运行 ----
suppressPackageStartupMessages(library(MatrixEQTL))

load_sliced <- function(f) {
  sd <- SlicedData$new()
  sd$fileDelimiter <- "\t"
  sd$fileOmitCharacters <- "NA"
  sd$fileSkipRows <- 1
  sd$fileSkipColumns <- 1
  sd$fileSliceSize <- slice_size
  sd$LoadFile(f)
  sd
}

useModel <- switch(model_name,
                   linear       = modelLINEAR,
                   anova        = modelANOVA,
                   linear_cross = modelLINEAR_CROSS)

snps <- load_sliced(snps_f)
gene <- load_sliced(gene_f)

cvrt <- SlicedData$new()
cvrt$fileDelimiter <- "\t"
cvrt$fileOmitCharacters <- "NA"
cvrt$fileSkipRows <- 1
cvrt$fileSkipColumns <- 1
cvrt$fileSliceSize <- slice_size
if (has_cov) cvrt$LoadFile(cov_f)

if (verbose) {
  cat("数据加载完成：model=", model_name, "；threads=", threads,
      "；slice_size=", slice_size, "\n", sep = "")
}

me <- Matrix_eQTL_main(
  snps = snps,
  gene = gene,
  cvrt = cvrt,
  output_file_name = trans_file,
  pvOutputThreshold = pv_threshold,
  useModel = useModel,
  errorCovariance = numeric(),
  verbose = verbose,
  output_file_name.cis = cis_file,
  pvOutputThreshold.cis = pv_threshold_cis,
  snpspos = snpspos,
  genepos = genepos,
  cisDist = cis_dist,
  pvalue.hist = pvalue_hist,
  min.pv.by.genesnp = FALSE,
  noFDRsaveMemory = FALSE
)

## ---- 结果自检与标记 ----
check_out <- function(f, tag) {
  ok <- file.exists(f) && file.info(f)$size > 0
  if (!ok) warning(tag, " 输出文件为空或未生成（阈值过严 / 输入无显著关联）: ", f, call. = FALSE)
  ok
}

trans_ok <- check_out(trans_file, "trans")
if (nzchar(cis_file)) {
  cis_ok <- check_out(cis_file, "cis")
} else {
  cis_ok <- FALSE
}

if (trans_ok) cat("RMATRIXEQTL_OK output=", trans_file, "\n", sep = "")
if (cis_ok)   cat("RMATRIXEQTL_OK_CIS output=", cis_file, "\n", sep = "")
cat("Matrix eQTL version:", as.character(packageVersion("MatrixEQTL")), "\n")
cat("all.eqtls", nrow(me$all$eqtls), "| cis.eqtls", nrow(me$cis$eqtls), "\n")
