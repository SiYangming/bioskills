#!/usr/bin/env bash
# qiime2_pipeline — Moving Pictures 扩增子档案脚本（远程取数 + DADA2 主链）
#
# 教程：https://amplicon-docs.qiime2.org/en/latest/tutorials/moving-pictures/
# 安装：见 modules/qiime2/README.md（官方 conda / quay.io/qiime2/amplicon）
#
# 前置：已激活 QIIME 2 环境（qiime 在 PATH）。在空目录执行本脚本。
# 参数（示例值来自官方教程；换数据时按 demux/table.qzv 自调）：
#   TRUNC_LEN=120  SAMPLING_DEPTH=1103
set -euo pipefail

TRUNC_LEN="${TRUNC_LEN:-120}"
SAMPLING_DEPTH="${SAMPLING_DEPTH:-1103}"
DATA_BASE="${DATA_BASE:-https://moving-pictures-tutorial.readthedocs.io/en/latest/data/moving-pictures}"
CLASSIFIER_URL="${CLASSIFIER_URL:-https://data.qiime2.org/classifiers/sklearn-1.4.2/greengenes/gg-13-8-99-515-806-nb-classifier.qza}"

command -v qiime >/dev/null || { echo "[ERROR] 未找到 qiime，先按 modules/qiime2 安装" >&2; exit 1; }

## 0. 远程获取示例输入
wget -O sample-metadata.tsv "${DATA_BASE}/sample-metadata.tsv"
wget -O emp-single-end-sequences.zip "${DATA_BASE}/emp-single-end-sequences.zip"
unzip -o -d emp-single-end-sequences emp-single-end-sequences.zip
wget -O gg-13-8-99-515-806-nb-classifier.qza "${CLASSIFIER_URL}"

## 1. 导入 + demux
mkdir -p 01.import 02.demux
qiime tools import \
  --type EMPSingleEndSequences \
  --input-path emp-single-end-sequences \
  --output-path 01.import/emp-single-end-sequences.qza

qiime demux emp-single \
  --i-seqs 01.import/emp-single-end-sequences.qza \
  --m-barcodes-file sample-metadata.tsv \
  --m-barcodes-column barcode-sequence \
  --o-per-sample-sequences 02.demux/demux.qza

qiime demux summarize \
  --i-data 02.demux/demux.qza \
  --o-visualization 02.demux/demux.qzv

## 2. DADA2 特征表（默认主链；Deblur 见教程，此处不双跑）
mkdir -p 03.feature_table
qiime dada2 denoise-single \
  --i-demultiplexed-seqs 02.demux/demux.qza \
  --p-trim-left 0 \
  --p-trunc-len "${TRUNC_LEN}" \
  --o-representative-sequences 03.feature_table/rep-seqs.qza \
  --o-table 03.feature_table/table.qza \
  --p-n-threads 0

qiime feature-table summarize \
  --i-table 03.feature_table/table.qza \
  --o-visualization 03.feature_table/table.qzv \
  --m-sample-metadata-file sample-metadata.tsv
qiime feature-table tabulate-seqs \
  --i-data 03.feature_table/rep-seqs.qza \
  --o-visualization 03.feature_table/rep-seqs.qzv

## 3. 系统发育
mkdir -p 04.phylogeny
qiime alignment mafft \
  --i-sequences 03.feature_table/rep-seqs.qza \
  --p-n-threads -1 \
  --o-alignment 04.phylogeny/aligned-rep-seqs.qza
qiime alignment mask \
  --i-alignment 04.phylogeny/aligned-rep-seqs.qza \
  --o-masked-alignment 04.phylogeny/masked-aligned-rep-seqs.qza
qiime phylogeny fasttree \
  --i-alignment 04.phylogeny/masked-aligned-rep-seqs.qza \
  --p-n-threads -1 \
  --o-tree 04.phylogeny/unrooted-tree.qza
qiime phylogeny midpoint-root \
  --i-tree 04.phylogeny/unrooted-tree.qza \
  --o-rooted-tree 04.phylogeny/rooted-tree.qza

## 4. 多样性
mkdir -p 05.diversity
qiime diversity core-metrics-phylogenetic \
  --i-phylogeny 04.phylogeny/rooted-tree.qza \
  --i-table 03.feature_table/table.qza \
  --p-sampling-depth "${SAMPLING_DEPTH}" \
  --m-metadata-file sample-metadata.tsv \
  --output-dir 05.diversity/core-metrics-results

qiime diversity alpha-group-significance \
  --i-alpha-diversity 05.diversity/core-metrics-results/faith_pd_vector.qza \
  --m-metadata-file sample-metadata.tsv \
  --o-visualization 05.diversity/core-metrics-results/faith-pd-group-significance.qzv
qiime diversity alpha-group-significance \
  --i-alpha-diversity 05.diversity/core-metrics-results/evenness_vector.qza \
  --m-metadata-file sample-metadata.tsv \
  --o-visualization 05.diversity/core-metrics-results/evenness-group-significance.qzv

qiime diversity beta-group-significance \
  --i-distance-matrix 05.diversity/core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file sample-metadata.tsv \
  --m-metadata-column body-site \
  --o-visualization 05.diversity/core-metrics-results/unweighted-unifrac-body-site-significance.qzv \
  --p-pairwise
qiime diversity beta-group-significance \
  --i-distance-matrix 05.diversity/core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file sample-metadata.tsv \
  --m-metadata-column subject \
  --o-visualization 05.diversity/core-metrics-results/unweighted-unifrac-subject-significance.qzv \
  --p-pairwise

qiime emperor plot \
  --i-pcoa 05.diversity/core-metrics-results/unweighted_unifrac_pcoa_results.qza \
  --m-metadata-file sample-metadata.tsv \
  --p-custom-axes days-since-experiment-start \
  --o-visualization 05.diversity/core-metrics-results/unweighted-unifrac-emperor.qzv
qiime emperor plot \
  --i-pcoa 05.diversity/core-metrics-results/bray_curtis_pcoa_results.qza \
  --m-metadata-file sample-metadata.tsv \
  --p-custom-axes days-since-experiment-start \
  --o-visualization 05.diversity/core-metrics-results/bray-curtis-emperor.qzv

## 5. 物种注释（预训练 classifier；教程另有现场训练 suboptimal 分类器的写法）
mkdir -p 06.taxonomy
qiime feature-classifier classify-sklearn \
  --i-classifier gg-13-8-99-515-806-nb-classifier.qza \
  --i-reads 03.feature_table/rep-seqs.qza \
  --o-classification 06.taxonomy/taxonomy.qza
qiime metadata tabulate \
  --m-input-file 06.taxonomy/taxonomy.qza \
  --o-visualization 06.taxonomy/taxonomy.qzv
qiime taxa barplot \
  --i-table 03.feature_table/table.qza \
  --i-taxonomy 06.taxonomy/taxonomy.qza \
  --m-metadata-file sample-metadata.tsv \
  --o-visualization 06.taxonomy/taxa-bar-plots.qzv

## 6. ANCOM（gut × subject；官方新教程多用 ancombc，经典 ancom 仍可用）
mkdir -p 07.ancom
qiime feature-table filter-samples \
  --i-table 03.feature_table/table.qza \
  --m-metadata-file sample-metadata.tsv \
  --p-where '[body-site]="gut"' \
  --o-filtered-table 07.ancom/gut-table.qza
qiime composition add-pseudocount \
  --i-table 07.ancom/gut-table.qza \
  --o-composition-table 07.ancom/comp-gut-table.qza
qiime composition ancom \
  --i-table 07.ancom/comp-gut-table.qza \
  --m-metadata-file sample-metadata.tsv \
  --m-metadata-column subject \
  --o-visualization 07.ancom/ancom-subject.qzv

qiime taxa collapse \
  --i-table 07.ancom/gut-table.qza \
  --i-taxonomy 06.taxonomy/taxonomy.qza \
  --p-level 6 \
  --o-collapsed-table 07.ancom/gut-table-l6.qza
qiime composition add-pseudocount \
  --i-table 07.ancom/gut-table-l6.qza \
  --o-composition-table 07.ancom/comp-gut-table-l6.qza
qiime composition ancom \
  --i-table 07.ancom/comp-gut-table-l6.qza \
  --m-metadata-file sample-metadata.tsv \
  --m-metadata-column subject \
  --o-visualization 07.ancom/l6-ancom-subject.qzv

echo "[OK] qiime2_pipeline 完成。可视化：qiime tools view <file.qzv>"
