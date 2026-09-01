# Ribo-seq 分析运行指南（RUN.md）

本文档假设你当前所在目录为本项目根目录：

```bash
cd /Users/siyangming/nextflow_nf_core/Ribo-seq
```

所有路径均以该目录为相对基准，默认你使用的是类 Unix 环境（Linux/macOS）。

---

## 0. 准备环境与依赖

1. 按照仓库自带的安装说明完成依赖安装：

   - 参考：[Installation/README.md](Installation/README.md)
   - 包括但不限于：conda、fastQC、cutadapt、bowtie2、UMI-tools、RSEM、samtools、R（含 DESeq2、tidyverse 等）、Python3 等。

2. 创建并激活分析环境（示例）：

   ```bash
   conda activate RNAseq
   ```

3. 将 Python 脚本目录加入 PATH（可选但强烈推荐）：

   假设 `Python_scripts` 在本项目根目录：

   ```bash
   echo 'export PATH=$PATH:'"$(pwd)/Python_scripts" >> ~/.bashrc
   source ~/.bashrc
   ```

---

## 1. 配置公共变量

在运行任何 Shell 或 R 脚本前，必须先配置：

- Shell 公共配置：[Shell_scripts/common_variables.sh](Shell_scripts/common_variables.sh)
- R 公共配置：[R_scripts/common_variables.R](R_scripts/common_variables.R)

1. 编辑 `Shell_scripts/common_variables.sh`：

   重点检查和填写：

   - `parent_dir`：本次实验父目录（建议为当前仓库外的一个目录，用于存放数据和结果）。
   - `RPF_sample_names`、`Total_sample_names`：RPF 与 Totals 的样本名（不含 `.fastq` 后缀）。
   - 适配子序列（3' adaptor）以及 UMI 结构（如果实验使用 UMI）。
   - 比对所用转录组/基因组 FASTA 路径。
   - RSEM index 路径。
   - region lengths `csv` 文件路径（包含 transcript_ID, 5'UTR, CDS, 3'UTR 长度）。

2. 编辑 `R_scripts/common_variables.R`：

   重点检查和填写：

   - `parent_dir`：必须与 `common_variables.sh` 中保持一致。
   - `RPF_sample_names`、`Total_sample_names`：与 Shell 脚本中保持一致。
   - RPF/Totals 分析中感兴趣的 read 长度范围（用于 QC 图）。

> 建议在所有脚本中保持 sample 名称与 parent_dir 完全一致，否则后续路径会对不上。

---

## 2. 构建目录结构

在父目录中创建标准目录结构，用于存放原始和处理后的数据：

```bash
bash Shell_scripts/makeDirs.sh
```

执行后，会在 `parent_dir` 下创建诸如 `fastq_files`, `Analysis`, `plots` 等子目录，后续所有脚本都假定这些目录存在。

---

## 3. 准备原始 FASTQ 数据

1. 将原始 RPF 与 Totals `*.fastq` 或 `*.fastq.gz` 放入 `parent_dir/fastq_files`。

2. 如果需要从 GEO 下载：

   ```bash
   bash Shell_scripts/accessory_scripts/download_fastq_files.sh
   ```

3. 如果手头是原始测序 bcl 文件，需要先进行 demultiplex：

   ```bash
   bash Shell_scripts/accessory_scripts/demultiplex.sh
   ```

4. 如需解压或重命名，可使用：

   - `Shell_scripts/accessory_scripts/unzip_fastq_files.sh`
   - `Shell_scripts/accessory_scripts/rename_fastq_files.sh`

在继续之前，确认 `fastq_files` 内的文件名与 `common_variables.sh` 中设置的样本前缀一致。

---

## 4. 处理 Totals（标准 RNA‑seq）

Totals 流程负责生成基因/转录本表达量，并提供后续 DESeq2 和“最丰度转录本”计算所需的输入。

你可以选择：

- 一键脚本：`bash Shell_scripts/Totals_all.sh`
- 或按步骤单独运行（更容易调试与理解）：

1. 初步 QC（fastQC）

   ```bash
   bash Shell_scripts/Totals_0_QC.sh
   ```

   - 输出 fastQC 报告到 `parent_dir/fastq_files/fastQC`，务必人工查看。

2. 去接头与质量过滤

   ```bash
   bash Shell_scripts/Totals_1_adaptor_removal.sh
   ```

   - 使用 cutadapt 去除 3' adaptor，剪切低质量碱基，过滤过短 reads。

3. UMI 处理（如果使用了 UMI）

   - 提取 UMI：

     ```bash
     bash Shell_scripts/Totals_2_extract_UMIs.sh
     ```

   - 如果实验没有 UMI：**跳过本步骤**，并确保后续脚本的输入文件名与实际文件对应。

4. 比对到转录组

   ```bash
   bash Shell_scripts/Totals_3a_align_reads_transcriptome.sh
   ```

5. 可选：比对到基因组（例如查看 mapping 质量）

   ```bash
   bash Shell_scripts/Totals_3b_align_reads_genome.sh
   ```

6. 去重复（如使用 UMI）

   - 对转录组 BAM 去重复：

     ```bash
     bash Shell_scripts/Totals_4a_deduplication_transcriptome.sh
     ```

   - 对基因组 BAM 去重复（如需要）：

     ```bash
     bash Shell_scripts/Totals_4b_deduplication_genome.sh
     ```

7. RSEM 定量（基因与转录本）

   ```bash
   bash Shell_scripts/Totals_5_isoform_quantification.sh
   ```

   - 输出 `.genes.results` 与 `.isoforms.results`，供 DESeq2 与“最丰度转录本”计算使用。

8. 生成最丰度转录本 FASTA 与 read counts

   ```bash
   bash Shell_scripts/Totals_6a_write_most_abundant_transcript_fasta.sh
   bash Shell_scripts/Totals_6b_extract_read_counts.sh
   ```

   - `Totals_6a` 生成每个基因的代表转录本 FASTA。
   - `Totals_6b` 从 BAM 中提取 read counts，作为 R 下游脚本输入。

---

## 5. 处理 RPFs（Ribo‑seq）

同样可以使用一键脚本：

```bash
bash Shell_scripts/RPFs_all.sh
```

或按步骤运行：

1. 初步 QC：

   ```bash
   bash Shell_scripts/RPFs_0_QC.sh
   ```

2. 去接头：

   ```bash
   bash Shell_scripts/RPFs_1_adaptor_removal.sh
   ```

3. UMI 处理（如果使用了 UMI）：

   ```bash
   bash Shell_scripts/RPFs_2_extract_UMIs.sh
   ```

4. 比对 reads：

   ```bash
   bash Shell_scripts/RPFs_3_align_reads.sh
   ```

5. 去重复：

   ```bash
   bash Shell_scripts/RPFs_4_deduplication.sh
   ```

6. 提取各区域 read 计数（所有长度）：

   ```bash
   bash Shell_scripts/RPFs_5_Extract_counts_all_lengths.sh
   ```

7. 区域级计数与 QC：

   ```bash
   bash Shell_scripts/RPFs_6a_summing_region_counts.sh
   bash Shell_scripts/RPFs_6b_summing_spliced_counts.sh
   bash Shell_scripts/RPFs_6c_periodicity.sh
   bash Shell_scripts/RPFs_6d_extract_read_counts.sh
   ```

8. 最终计数矩阵与 CDS/UTR 分拆：

   ```bash
   bash Shell_scripts/RPFs_7_Extract_final_counts.sh
   bash Shell_scripts/RPFs_8a_CDS_counts.sh
   bash Shell_scripts/RPFs_8b_UTR5_counts.sh
   bash Shell_scripts/RPFs_8c_counts_to_csv.sh
   bash Shell_scripts/RPFs_8d_count_codon_occupancy.sh
   ```

上述步骤完成后，`parent_dir/Analysis` 下会生成一系列计数矩阵和中间结果，供 R 下游分析使用。

---

## 6. Python FASTA 预处理（可选但推荐）

如果你使用 GENCODE 提供的蛋白编码 FASTA，建议先进行过滤与重格式化：

1. 过滤 GENCODE FASTA：

   ```bash
   python3 Python_scripts/Filtering_GENCODE_FASTA.py  # 具体参数见脚本头部说明
   ```

2. 重格式化 FASTA 与导出注释 CSV：

   ```bash
   python3 Python_scripts/Reformatting_GENCODE_FASTA.py  # 具体参数见脚本头部说明
   ```

生成的过滤/重格式化 FASTA 与 CSV 文件会在 R 分析中用于长度信息和区段注释。

---

## 7. R 下游分析总览

在运行 R 脚本前，确保工作目录为项目根目录，且 `R_scripts/common_variables.R` 已正确配置：

```bash
cd /Users/siyangming/nextflow_nf_core/Ribo-seq
```

推荐使用 `Rscript` 直接运行：

```bash
Rscript R_scripts/xxx.R
```

下面按模块给出建议顺序。

### 7.1 计算最丰度转录本

输入：Totals 流程中 RSEM 的 isoform 定量结果。

```bash
Rscript R_scripts/calculate_most_abundant_transcript.R
```

输出：

- `Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv`
- `Analysis/most_abundant_transcripts/most_abundant_transcripts.txt`

后续多种 R 脚本会用到这些文件。

### 7.2 DESeq2 差异分析

依赖：Totals/RPFs 计数矩阵和 `most_abundant_transcripts_IDs.csv`。

1. RPFs：

   ```bash
   Rscript R_scripts/DESeq2/DESeq2_RPFs.R
   ```

2. Totals：

   ```bash
   Rscript R_scripts/DESeq2/DESeq2_Totals.R
   ```

3. 翻译效率（TE）：

   ```bash
   Rscript R_scripts/DESeq2/DESeq2_TE.R
   ```

4. 差异分析可视化与汇总（生成 `merged_DESeq2.csv` 等）：

   ```bash
   Rscript R_scripts/DESeq2/DE_analysis_plots.R
   ```

### 7.3 QC 图（RPF/Totals 文库质量）

依赖：Shell 流程产生的 read counts 与 region counts。

示例顺序：

```bash
Rscript R_scripts/QC/RPFs_read_counts.R
Rscript R_scripts/QC/Totals_read_counts.R
Rscript R_scripts/QC/heatmaps.R
Rscript R_scripts/QC/offset_plots.R
Rscript R_scripts/QC/offset_aligned_single_nt_plots.R
Rscript R_scripts/QC/periodicity.R
Rscript R_scripts/QC/region_counts.R
```

### 7.4 GSEA 与 GO 精简（fgsea + rrvgo）

1. 运行 fgsea，生成各 pathway 的富集结果：

   ```bash
   Rscript R_scripts/gsea/fgsea.R
   Rscript R_scripts/gsea/fgsea_overlaid_scatters.R
   ```

2. 读取人/鼠 GSEA 通路注释（按需要）：

   ```bash
   Rscript R_scripts/gsea/read_mouse_GSEA_pathways.R
   # 或
   Rscript R_scripts/gsea/read_human_GSEA_pathways.R
   ```

3. 使用 rrvgo 对 GO terms 进行相似性聚合和 treemap/bar 图绘制：

   ```bash
   Rscript R_scripts/gsea/rrvgo.R
   ```

### 7.5 feature_properties（UTR/CDS 特征与梯度提升模型）

1. 特征分布可视化：

   ```bash
   Rscript R_scripts/feature_properties/plot_feature_properties.R
   ```

2. 梯度提升模型（gradient boosting）分析 TE 与特征之间的关系：

   ```bash
   Rscript R_scripts/feature_properties/gradient_boosting.R
   ```

### 7.6 meta_plots（关键：包括 plot_individual_mRNAs.R）

此部分利用 RPF 的位置分布绘制 meta profiles 和单基因 profile。

1. 对单转录本计数做 TPM 归一化并保存列表：

   ```bash
   Rscript R_scripts/meta_plots/normalise_individual_transcript_counts.R
   ```

   输出：`Counts_files/R_objects/counts_list.Rdata`

2. 对所有转录本进行区域分箱与 outlier 过滤：

   ```bash
   Rscript R_scripts/meta_plots/bin_data.R
   ```

   输出：

   - `Counts_files/R_objects/binned_list.Rdata`
   - `Counts_files/R_objects/single_nt_list.Rdata`

3. 利用分箱结果绘制全局 meta plots：

   ```bash
   Rscript R_scripts/meta_plots/plot_binned_data.R
   ```

4. 绘制单个或基因集的 mRNA meta profile（你当前打开的脚本）：

   ```bash
   Rscript R_scripts/meta_plots/plot_individual_mRNAs.R
   ```

   - 依赖文件：
     - `Counts_files/R_objects/counts_list.Rdata`
     - `Analysis/most_abundant_transcripts/most_abundant_transcripts_IDs.csv`
     - `Analysis/DESeq2_output/merged_DESeq2.csv`
     - 转录本 region lengths `csv`
   - 脚本中可以直接修改：
     - `control` / `treatment` 名称
     - `plot_single_transcripts` 中的 `gene` 列表与输出子目录

5. Sel‑RiboSeq（如有 disome/TCP 数据）：

   ```bash
   Rscript R_scripts/meta_plots/bin_data_sel_TCP
   ```

   - 用于生成 disome 相关的分箱与 single‑nt 列表。

### 7.7 交互散点与密码子占据

1. 交互式 TE 散点图（Glimma）：

   ```bash
   Rscript R_scripts/Interactive_scatters.R
   ```

   - 输出 HTML，在 `plots/Interactive_scatters` 下。

2. 密码子占据分析：

   ```bash
   Rscript R_scripts/codon_occupancy.R
   ```

   - 输入：Shell/Python 流程生成的 codon 计数文件。

---

## 8. 从零到运行 plot_individual_mRNAs.R 的最小步骤汇总

如果你的目标是**最终能够运行 `plot_individual_mRNAs.R` 绘制单基因 meta profile**，从空项目开始的最小必要步骤可以简写为：

1. 安装依赖（见第 0 节）。
2. 配置 `Shell_scripts/common_variables.sh` 与 `R_scripts/common_variables.R`（见第 1 节）。
3. 运行 `makeDirs.sh` 创建目录结构（第 2 节）。
4. 将 RPF 与 Totals 的 FASTQ 放入 `fastq_files`（第 3 节）。
5. 跑完 Totals 流程（第 4 节），获得 RSEM 结果。
6. 跑完 RPF 流程（第 5 节），获得 CDS/UTR 计数。
7. 在 R 中运行：

   ```bash
   Rscript R_scripts/calculate_most_abundant_transcript.R
   Rscript R_scripts/DESeq2/DESeq2_Totals.R
   Rscript R_scripts/DESeq2/DESeq2_RPFs.R
   Rscript R_scripts/DESeq2/DESeq2_TE.R
   Rscript R_scripts/DESeq2/DE_analysis_plots.R
   Rscript R_scripts/meta_plots/normalise_individual_transcript_counts.R
   ```

8. 最后，运行单基因 meta plot：

   ```bash
   Rscript R_scripts/meta_plots/plot_individual_mRNAs.R
   ```

   在脚本内部调整：

   - `control` 与 `treatment` 名称；
   - `plot_single_transcripts()` 调用中的 `gene` 名单与输出子目录。

---

## 9. 使用 `testdata/` 进行端到端测试示例

本节给出一个**完整可复现的示例**，说明如何用仓库自带的
`/Users/siyangming/nextflow_nf_core/Ribo-seq/testdata` 中的下采样 FASTQ
快速跑通从 Shell 到 R 的关键步骤，最终跑到 `plot_individual_mRNAs.R`。

> 注意：`testdata/` 只提供了小规模 FASTQ 和部分辅助 FASTA，  
> 比对所需的参考序列（rRNA/tRNA/转录组/基因组 FASTA 及其索引）仍需要你自己准备。

### 9.1 选择测试用 parent_dir 并复制 FASTQ

1. 建议在仓库外创建一个专门用于测试的父目录，例如：

   ```bash
   TEST_PARENT_DIR=/Users/siyangming/nextflow_nf_core/Ribo-seq_test_run
   mkdir -p "$TEST_PARENT_DIR"
   ```

2. 编辑 `Shell_scripts/common_variables.sh` 和 `R_scripts/common_variables.R`，
   将 `parent_dir` 都改为同一个测试目录，例如：

   - `Shell_scripts/common_variables.sh` 中：

     ```bash
     parent_dir='/Users/siyangming/nextflow_nf_core/Ribo-seq_test_run'
     ```

   - `R_scripts/common_variables.R` 中：

     ```r
     parent_dir <- "/Users/siyangming/nextflow_nf_core/Ribo-seq_test_run"
     ```

3. 在测试目录中创建标准子目录结构（会同时创建 `fastq_files` 等）：

   ```bash
   cd /Users/siyangming/nextflow_nf_core/Ribo-seq
   bash Shell_scripts/makeDirs.sh
   ```

4. 将 `testdata/GSE182201/` 中的下采样 FASTQ 复制到测试目录的 `fastq_files`：

   ```bash
   TEST_PARENT_DIR=/Users/siyangming/nextflow_nf_core/Ribo-seq_test_run
   cp testdata/GSE182201/*.fastq.gz "$TEST_PARENT_DIR/fastq_files"
   ```

   复制后，`$parent_dir/fastq_files` 下会包含如下文件（示例）：

   - 成对（paired‑end）Totals（RNA‑seq）示例：
     - `SRX11780879_SRR15480782_chr20_1.fastq.gz`
     - `SRX11780879_SRR15480782_chr20_2.fastq.gz`
     - `SRX11780880_SRR15480783_chr20_1.fastq.gz`
     - `SRX11780880_SRR15480783_chr20_2.fastq.gz`
     - `SRX11780881_SRR15480784_chr20_1.fastq.gz`
     - `SRX11780881_SRR15480784_chr20_2.fastq.gz`
     - `SRX11780882_SRR15480785_chr20_1.fastq.gz`
     - `SRX11780882_SRR15480785_chr20_2.fastq.gz`
     - `SRX11780883_SRR15480786_chr20_1.fastq.gz`
     - `SRX11780883_SRR15480786_chr20_2.fastq.gz`
     - `SRX11780884_SRR15480787_chr20_1.fastq.gz`
     - `SRX11780884_SRR15480787_chr20_2.fastq.gz`

   - 单端（single‑end）RPF（Ribo‑seq）示例：
     - `SRX11780885_SRR15480788_chr20_1.fastq.gz`
     - `SRX11780886_SRR15480789_chr20_1.fastq.gz`
     - `SRX11780887_SRR15480790_chr20_1.fastq.gz`
     - `SRX11780888_SRR15480791_chr20_1.fastq.gz`
     - `SRX11780889_SRR15480792_chr20_1.fastq.gz`
     - `SRX11780890_SRR15480793_chr20_1.fastq.gz`

> 说明：这些 FASTQ 原本是通过 `testdata/make_test_data.sh` 从公开数据下采样得到，  
> 仓库已经提供结果，通常不需要你再次运行该脚本。

### 9.2 在 common_variables 中指定测试样本名

在 `Shell_scripts/common_variables.sh` 顶部，按测试数据设置样本名：

```bash
###filenames
# RPF（单端）样本名（不带 .fastq/.fastq.gz 后缀）
RPF_filenames='SRX11780885_SRR15480788_chr20 SRX11780886_SRR15480789_chr20 SRX11780887_SRR15480790_chr20 SRX11780888_SRR15480791_chr20 SRX11780889_SRR15480792_chr20 SRX11780890_SRR15480793_chr20'

# Totals（成对）样本名（不带 .fastq/.fastq.gz 后缀）
Totals_filenames='SRX11780879_SRR15480782_chr20 SRX11780880_SRR15480783_chr20 SRX11780881_SRR15480784_chr20 SRX11780882_SRR15480785_chr20 SRX11780883_SRR15480786_chr20 SRX11780884_SRR15480787_chr20'
```

其余参数（接头、FASTAs、索引路径等）保持与你本地环境一致即可。  
如果只是做最小验证，你可以先保证：

- `rRNA_fasta`、`tRNA_fasta` 指向有效的 rRNA/tRNA FASTA；
- `pc_fasta`、`rsem_index`、`STAR_index`、`STAR_GTF` 指向已经构建好的参考与索引。

> 提示：`testdata/` 下的 `hg38-mature-tRNAs-dna.fasta` 等文件可作为测试环境中
> tRNA/rRNA FASTA 的示例来源，但真实分析时建议使用全基因组/全转录组版本。

### 9.3 用测试数据跑 Shell 流程

配置好 `common_variables.sh` 之后，在项目根目录运行：

```bash
cd /Users/siyangming/nextflow_nf_core/Ribo-seq
```

1. 先跑 Totals（RNA‑seq）流程：

   ```bash
   bash Shell_scripts/Totals_all.sh
   ```

   或按步骤运行 `Totals_0_QC.sh` ~ `Totals_6b_extract_read_counts.sh`（见第 4 节）。

2. 再跑 RPF（Ribo‑seq）流程：

   ```bash
   bash Shell_scripts/RPFs_all.sh
   ```

   或按步骤运行 `RPFs_0_QC.sh` ~ `RPFs_8d_count_codon_occupancy.sh`（见第 5 节）。

完成后，测试用 `parent_dir`（例如 `Ribo-seq_test_run`）下应该有：

- `Counts_files/` 下的各种计数矩阵；
- `Analysis/` 下的 region_counts/CDS_counts/UTR5_counts 等；
- `plots/` 下的 QC 图（fastQC、periodicity、heatmaps 等）。

### 9.4 用测试数据跑 R 脚本直到 plot_individual_mRNAs.R

保持工作目录在项目根目录，并确保 `R_scripts/common_variables.R` 中的 `parent_dir`
与 Shell 一致：

```bash
cd /Users/siyangming/nextflow_nf_core/Ribo-seq
```

用测试数据跑完从最丰度转录本到单基因 meta plot 的关键步骤：

```bash
# 计算最丰度转录本
Rscript R_scripts/calculate_most_abundant_transcript.R

# DESeq2：Totals、RPFs 与 TE
Rscript R_scripts/DESeq2/DESeq2_Totals.R
Rscript R_scripts/DESeq2/DESeq2_RPFs.R
Rscript R_scripts/DESeq2/DESeq2_TE.R
Rscript R_scripts/DESeq2/DE_analysis_plots.R

# meta_plots：单转录本计数归一化与列表
Rscript R_scripts/meta_plots/normalise_individual_transcript_counts.R

# meta_plots：分箱与全局 meta plots（可选，但推荐）
Rscript R_scripts/meta_plots/bin_data.R
Rscript R_scripts/meta_plots/plot_binned_data.R
```

最后，运行单基因 meta plot：

```bash
Rscript R_scripts/meta_plots/plot_individual_mRNAs.R
```

在 `plot_individual_mRNAs.R` 中，可以根据测试条件修改：

- `control` 与 `treatment` 分组名称；
- `plot_single_transcripts()` 中的 `gene` 列表；
- 输出子目录名（例如 `dir = "testdata_GSE182201"`）。

成功运行后，你应在：

- `plots/binned_plots/single_transcripts/testdata_GSE182201`（或你指定的目录）下看到
  针对测试基因的单基因 meta plots；
- `Analysis/DESeq2_output` 下看到基于测试数据的差异分析结果
 （`merged_DESeq2.csv` 等）。

通过上述步骤，你可以在较短时间内确认：

- Shell 预处理与比对流程在当前环境可以正常运行；
- R 下游脚本在测试数据上可以顺利跑通并生成图表。

在此基础上，将 `parent_dir`、样本名和参考路径替换为真实项目配置，即可用于正式分析。 
