#!/usr/bin/env Rscript
# =============================================================================
# run_quantifypolya.R — QuantifyPolyA 统一分析驱动（params.tsv / 独立 CLI 双模式）
#
# QuantifyPolyA（R 包，sourceforge quantifypoly-a）用于长读 / 3' end RNA-seq
# poly(A) 位点定量与 APA（alternative polyadenylation）动态度量，核心流程：
#   Load.PolyA(BED 目录/文件) -> [Remove.IP(基因组 fasta)] -> Cluster.PolyA(PAC)
#   -> [Annotate.PolyA(gff)] -> [Filter.PolyA] -> Quantify.Canonical/Gene/Split/
#   CN CAPA(组间 APA 动态度量表)
#
# 用法一（params.tsv，native/main.py quant 子命令调用；无 `--` 开头即本模式）：
#   Rscript run_quantifypolya.R <params.tsv>
#   params.tsv 键（键<TAB>值）：bed_dir|bed_files outdir
#                  [fasta gff max_gapwidth min_count min_sample
#                   col_data contrast quant_mode threads save_rds quiet]
#
# 用法二（独立 CLI 直跑；参数名 - 与 _ 等价，--key value）：
#   Rscript run_quantifypolya.R --bed-dir Human_MAQC --outdir results \
#       --gff annotation.gff3 --col-data colData.tsv --contrast condition,Brain,UHR \
#       --quant-mode canonical --threads 8
#
# 产物（outdir 下）：
#   polyA_sites.tsv     聚类（+注释 + 每样本计数）后的 poly(A) 位点/簇全表
#   apa_<mode>.tsv      组间 APA 动态度量表（canonical|gene|split|cncapa；需
#                       gff + colData + contrast）
#   QuantifyPolyA.rds   QpolyA 对象（--save-rds TRUE，供 Visualize.PolyA 下游画图）
# 完成时打印 "QUANTIFYPOLYA_OK output=<polyA_sites.tsv> [apa=<...>]"。
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)

print_usage <- function(con = stdout()) {
  cat('run_quantifypolya.R — QuantifyPolyA poly(A) 定量与 APA 分析驱动\n',
      '用法:  Rscript run_quantifypolya.R <params.tsv>\n',
      '        Rscript run_quantifypolya.R --bed-dir <dir|file[,file]> --outdir <d> [选项]\n',
      '关键参数（--key value；- 与 _ 等价）:\n',
      '  --bed-dir <目录>   含每样本一个 .bed（4 列: seqnames strand coord score），\n',
      '                     文件名(去 .bed)即样本名；也可 --bed-dir a.bed,b.bed 传文件列表\n',
      '  --outdir <目录>    输出目录（必填；polyA_sites.tsv / apa_<mode>.tsv / rds）\n',
      '  --fasta <f>        基因组 FASTA（可选；做 Remove.IP 去除内部引发）\n',
      '  --gff <f>          基因注释 GFF3/GTF（可选；Annotate.PolyA，输出基因/UTR 注释\n',
      '                     与每样本计数；做 APA 动态度量必需）\n',
      '  --col-data <f>     实验设计表 TSV（可选；首列样本名=bed 文件名，须含 contrast 列\n',
      '                     与 condition 列；与 --contrast 一起启用组间 APA 度量）\n',
      '  --contrast <列,组1,组2>  如 condition,Brain,UHR（默认列 condition）\n',
      '  --quant-mode <m>   canonical|gene|split|cncapa（默认 canonical）\n',
      '  --max-gapwidth <n> PAC 聚类最大 gap（默认 24）   --threads <n|auto>\n',
      '  --min-count <n> --min-sample <n>  Filter.PolyA（默认不过滤）\n',
      '  --save-rds TRUE|FALSE（默认 FALSE）  --quiet TRUE|FALSE\n',
      sep = "")
}

cli_mode <- FALSE
if (length(args) >= 1 && any(grepl("^-", args))) cli_mode <- TRUE
if (!cli_mode && length(args) != 1) {
  print_usage(con = stderr())
  stop("用法错误：请提供 <params.tsv> 或一组 --key value 参数（--help 查看）", call. = FALSE)
}
if (any(args %in% c("-h", "--help"))) { print_usage(); quit(save = "no", status = 0) }

## ---- 键名归一化：去掉 -/_ 便于兼容两种命名习惯 ----
norm_key <- function(k) gsub("[-_]", "", tolower(k))
KEY_ALIAS <- c(
  beddir = "bed_dir", bedfiles = "bed_files", bed = "bed_dir",
  outdir = "outdir", out = "outdir",
  fasta = "fasta", genome = "fasta",
  gff = "gff", gff3 = "gff", annotation = "gff", gtf = "gff",
  colData = "col_data", coldata = "col_data", coldatafile = "col_data", design = "col_data",
  contrast = "contrast",
  quantmode = "quant_mode", mode = "quant_mode", quant = "quant_mode",
  maxgapwidth = "max_gapwidth", gapwidth = "max_gapwidth",
  mincount = "min_count", minsample = "min_sample",
  threads = "threads", cores = "threads", mccores = "threads",
  saverds = "save_rds", rds = "save_rds",
  quiet = "quiet"
)

read_params_file <- function(f) {
  par <- read.delim(f, header = FALSE, sep = "\t",
                    stringsAsFactors = FALSE, quote = "")
  p <- as.list(par$V2); names(p) <- par$V1
  p
}

parse_cli <- function(raw) {
  p <- list(); i <- 1L
  while (i <= length(raw)) {
    tok <- raw[i]
    if (grepl("^--", tok)) {
      kv <- sub("^--", "", tok)
      if (grepl("=", kv, fixed = TRUE)) {
        sp <- strsplit(kv, "=", fixed = TRUE)[[1]]; key <- sp[1]; val <- sp[2]
      } else {
        key <- kv
        if (i + 1L > length(raw)) stop("缺少参数值: --", kv, call. = FALSE)
        val <- raw[i + 1L]; i <- i + 1L
      }
      nk <- norm_key(key)
      if (!(nk %in% names(KEY_ALIAS))) stop("未知参数: --", key, "（--help 查看）", call. = FALSE)
      p[[KEY_ALIAS[[nk]]]] <- val
    } else {
      stop("无法识别参数: ", tok, "（CLI 模式参数需以 -- 开头）", call. = FALSE)
    }
    i <- i + 1L
  }
  p
}

p <- if (!cli_mode) read_params_file(args[1]) else parse_cli(args)

raw <- function(k) p[[k]]
num <- function(k, d) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.numeric(v) }
intv <- function(k, d) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.integer(v) }
chr <- function(k, d = NULL) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else as.character(v) }
bool <- function(k, d) { v <- raw(k); if (is.null(v) || is.na(v) || v == "") d else tolower(v) %in% c("true", "1", "yes", "t") }

## ---- 硬件探测 / 线程 ----
auto_cores <- function() {
  nc <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) NA_integer_)
  if (is.na(nc) || nc < 1) nc <- tryCatch(parallel::detectCores(), error = function(e) 4L)
  if (is.na(nc) || nc < 1) nc <- 4L
  max(1L, nc - 1L)
}
thr_raw <- chr("threads", "auto")
threads <- if (tolower(thr_raw) == "auto") auto_cores() else max(1L, intv("threads", 4L))
quiet <- bool("quiet", FALSE)

## ---- 输入与输出校验 ----
outdir <- chr("outdir", stop("缺少 outdir"))
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
if (!dir.exists(outdir) || file.access(outdir, mode = 2) != 0)
  stop("输出目录不可写: ", outdir, call. = FALSE)

bed_dir <- chr("bed_dir"); bed_files <- chr("bed_files")
if (!is.null(bed_files)) {
  files <- trimws(strsplit(bed_files, ",")[[1]])
} else if (!is.null(bed_dir) && dir.exists(bed_dir)) {
  files <- NULL
} else {
  stop("需要输入：--bed-dir <含 .bed 的目录> 或 --bed-files/--bed-dir <f1.bed,f2.bed>", call. = FALSE)
}

fasta <- chr("fasta"); gff <- chr("gff")
col_data_f <- chr("col_data"); contrast_s <- chr("contrast")
quant_mode <- tolower(chr("quant_mode", "canonical"))
if (!(quant_mode %in% c("canonical", "gene", "split", "cncapa")))
  stop("quant_mode 必须是 canonical|gene|split|cncapa（收到: ", quant_mode, "）", call. = FALSE)
max_gapwidth <- intv("max_gapwidth", 24L)
min_count <- intv("min_count", NA_integer_)
min_sample <- intv("min_sample", NA_integer_)
save_rds <- bool("save_rds", FALSE)

## ---- QuantifyPolyA 加载 ----
suppressPackageStartupMessages(library(QuantifyPolyA))
if (!quiet) cat("QuantifyPolyA", as.character(packageVersion("QuantifyPolyA")),
                "| threads =", threads, "\n")

## ---- 1) Load.PolyA ----
QpolyA <- if (!is.null(files)) {
  Load.PolyA(files = files)
} else {
  Load.PolyA(dir = bed_dir)
}
n_samples <- length(QpolyA@sample_names)
if (!quiet) cat("Loaded", n_samples, "samples:", paste(QpolyA@sample_names, collapse = ", "), "\n")

## ---- 2) Remove.IP（可选，需基因组 fasta）----
if (!is.null(fasta)) {
  if (!file.exists(fasta)) stop("Fasta 文件不存在: ", fasta, call. = FALSE)
  if (!quiet) cat("Remove internal priming events ...\n")
  QpolyA <- Remove.IP(QpolyA, fasta = fasta)
}

## ---- 3) Cluster.PolyA（加权密度峰聚类生成 PAC）----
if (!quiet) cat("Cluster poly(A) sites (max.gapwidth =", max_gapwidth, ") ...\n")
QpolyA <- Cluster.PolyA(QpolyA, max.gapwidth = max_gapwidth, mc.cores = threads)

## ---- 4) Annotate.PolyA + Filter.PolyA（可选，需 gff）----
if (!is.null(gff)) {
  if (!file.exists(gff)) stop("Annotation 文件不存在: ", gff, call. = FALSE)
  if (!quiet) cat("Annotate poly(A) sites with", gff, "...\n")
  QpolyA <- Annotate.PolyA(QpolyA, gff = gff)
  if (!is.na(min_count)) {
    if (is.na(min_sample)) min_sample <- 1L
    if (!quiet) cat("Filter.PolyA min_count =", min_count, "min_sample =", min_sample, "...\n")
    QpolyA <- Filter.PolyA(QpolyA, min_count = min_count, min_sample = min_sample)
  }
} else if (!is.na(min_count)) {
  warning("min_count/min_sample 需要 gff 注释（Filter.PolyA 作用于注释后计数表），已忽略", call. = FALSE)
}

## ---- 5) 输出 poly(A) 位点/簇全表 ----
sites_out <- file.path(outdir, "polyA_sites.tsv")
tab <- as.data.frame(QpolyA@polyA)
if (nrow(tab) > 0) {
  write.table(tab, sites_out, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
} else {
  warning("polyA 位点表为空（输入无有效位点？）", call. = FALSE)
  file.create(sites_out)
}

## ---- 6) 组间 APA 动态度量（可选，需 colData + contrast + gff 注释）----
apa_out <- NULL
if (!is.null(col_data_f) || !is.null(contrast_s)) {
  if (!is.null(gff) && file.exists(col_data_f)) {
    colData <- read.delim(col_data_f, header = TRUE, sep = "\t",
                          stringsAsFactors = FALSE, quote = "")
    if (ncol(colData) < 2) colData <- read.csv(col_data_f, stringsAsFactors = FALSE)
    rownames(colData) <- make.unique(as.character(colData[[1]]))
    colData[[1]] <- NULL
    if (is.null(colData$condition)) stop("colData 缺少 condition 列", call. = FALSE)
    bad <- setdiff(rownames(colData), QpolyA@sample_names)
    if (length(bad) > 0)
      stop("colData 行名与样本名不一致: ", paste(bad, collapse = ","),
           "（样本名 = bed 文件名去 .bed）", call. = FALSE)

    cc <- if (!is.null(contrast_s)) {
      v <- trimws(strsplit(contrast_s, ",")[[1]])
      if (length(v) != 3) stop("--contrast 应为 <组列>,<对照>,<处理>（如 condition,Brain,UHR）", call. = FALSE)
      v
    } else {
      c("condition",
        sort(unique(colData$condition))[1],
        sort(unique(colData$condition))[2])
    }
    if (!(cc[1] %in% colnames(colData))) stop("contrast 列 '", cc[1], "' 不在 colData 中", call. = FALSE)

    quant_fun <- switch(quant_mode,
                        canonical = Quantify.CanonicalAPA,
                        gene      = Quantify.GeneAPA,
                        split     = Quantify.SplitAPA,
                        cncapa    = Quantify.CNCAPA)
    if (!quiet) cat("Quantify", quant_mode, "APA dynamics:", cc[2], "vs", cc[3], "...\n")
    res <- quant_fun(QpolyA, colData = colData, contrast = cc)
    apa_out <- file.path(outdir, paste0("apa_", quant_mode, ".tsv"))
    write.table(as.data.frame(res), apa_out, sep = "\t", quote = FALSE,
                row.names = FALSE, col.names = TRUE)
  } else {
    warning("APA 动态度量需要 --gff 注释与存在的 --col-data 文件；已跳过量化，仅输出位点表",
            call. = FALSE)
  }
}

## ---- 7) RDS（可选，供 Visualize.PolyA 下游）----
if (save_rds) {
  rds_out <- file.path(outdir, "QuantifyPolyA.rds")
  saveRDS(QpolyA, rds_out)
  if (!quiet) cat("Saved QpolyA object ->", rds_out, "\n")
}

## ---- 结果自检与打标 ----
ok_sites <- file.exists(sites_out) && file.info(sites_out)$size > 0
if (!ok_sites) warning("polyA_sites.tsv 为空或未生成", call. = FALSE)
cat("QUANTIFYPOLYA_OK output=", sites_out, sep = "")
if (!is.null(apa_out) && file.exists(apa_out) && file.info(apa_out)$size > 0)
  cat(" apa=", apa_out, sep = "")
cat("\n")
