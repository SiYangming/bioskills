# dada2 软件模块

> 汇总说明：本 README 记录 DADA2（R 包）的 native 实现用法与容器/conda 环境信息；安装方式见「环境安装」节。DADA2 以 R 包形态分发（无独立命令行二进制），本模块用 `Rscript` 驱动。

***

## native 实现

# dada2 / native — 自包含扩增子去噪驱动（Rscript）

DADA2 的本地自包含实现（`source_type: custom`、`type: native`）。DADA2 以 R 包分发、无独立 CLI，本驱动按子命令生成一段 R 脚本，再以 `Rscript <script>` 运行，覆盖 16S 扩增子去噪全链路；等价能力亦内置于 QIIME 2（`qiime dada2 denoise-single` / `denoise-paired`）。

## 功能

| 子命令                | R 函数                                            | 作用                              |
| ------------------ | ----------------------------------------------- | ------------------------------- |
| `filterAndTrim`    | `dada2::filterAndTrim()`                        | 质量过滤（5'/3' 端截短、maxEE、truncQ）    |
| `learnErrors`      | `dada2::learnErrors()`                          | 学习测序错误模型                        |
| `denoise` / `dada` | `dada2::dada()`                                 | 去噪核心（输出单核苷酸分辨率 ASVs）            |
| `mergePairs`       | `dada2::mergePairs()`                           | 双端读长合并                          |
| `makeSequenceTable` | `dada2::makeSequenceTable()`                   | 生成 ASV 序列表（样本×ASV）              |
| `removeBimera`     | `dada2::removeBimeraDenovo()`                   | 去嵌合体                            |

> DADA2 默认在去噪过程中自动进行嵌合体检测与去除；`removeBimera` 子命令用于显式二次去嵌合。

## 用法

```bash
# 单端 16S 全链路（CLI 直跑）
python main.py filterAndTrim sample_R1.fastq.gz --filt sample_R1.filt.fastq.gz \
    --trunc-len 120 --max-ee 2 --threads 8
python main.py learnErrors --reads sample_R1.filt.fastq.gz --output errF.rds --threads 8
python main.py denoise --reads sample_R1.filt.fastq.gz --error errF.rds \
    --output dadaF.rds --threads 8
python main.py makeSequenceTable merged.rds --output seqtab.rds
python main.py removeBimera seqtab.rds --output seqtab.nochim.rds

# 双端（filterAndTrim 给 --rev/--filt-rev；mergePairs 合并 R1/R2）
python main.py filterAndTrim sample_R1.fastq.gz --filt sample_R1.filt.fastq.gz \
    --rev sample_R2.fastq.gz --filt-rev sample_R2.filt.fastq.gz --trunc-len 120
python main.py mergePairs --dada-f dadaF.rds --dada-r dadaR.rds \
    --filt-f sample_R1.filt.fastq.gz --filt-r sample_R2.filt.fastq.gz --output mergers.rds

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 映射到 DADA2 的 `multithread` 参数。

## 实战示例：16S 扩增子去噪（DADA2）

DADA2（Divisive Amplicon Denoising Algorithm 2） 通过错误模型推断真实生物学序列，输出 ASVs（ Amplicon Sequence Variants，扩增子序列变异体），分辨率达单核苷酸水平，且支持多线程、单端/双端。以下为典型批量用法；等价能力由 `native/main.py` 的 `filterAndTrim` / `learnErrors` / `denoise` / `mergePairs` / `makeSequenceTable` / `removeBimera` 子命令提供（见上「用法」）。

### 1. 质量过滤（仅 5'/3' 端整体截短）

```bash
mkdir -p dada2_out && cd dada2_out
# 对多样本循环过滤：R1 -> R1.filt；双端再补 R2
for i in ../raw/*_R1.fastq.gz
do
    sample=$(basename $i _R1.fastq.gz)
    python ../native/main.py filterAndTrim "$i" --filt "${sample}_R1.filt.fastq.gz" \
        --rev "../raw/${sample}_R2.fastq.gz" \
        --filt-rev "${sample}_R2.filt.fastq.gz" \
        --trunc-len-f 120 --trunc-len-r 120 --max-ee 2 --threads 8
done
```

### 2. 学习错误模型 → 去噪 → 合并 → 序列表 → 去嵌合

```bash
python ../native/main.py learnErrors --reads "$(ls *_R1.filt.fastq.gz | paste -sd,)" \
    --output errF.rds --threads 8
python ../native/main.py denoise --reads "$(ls *_R1.filt.fastq.gz | paste -sd,)" \
    --error errF.rds --output dadaF.rds --threads 8
python ../native/main.py mergePairs --dada-f dadaF.rds --dada-r dadaR.rds \
    --filt-f "$(ls *_R1.filt.fastq.gz | paste -sd,)" \
    --filt-r "$(ls *_R2.filt.fastq.gz | paste -sd,)" --output mergers.rds
python ../native/main.py makeSequenceTable mergers.rds --output seqtab.rds
python ../native/main.py removeBimera seqtab.rds --output seqtab.nochim.rds
```

### 3. 参数说明

| 参数                  | 说明                                |
| ------------------- | --------------------------------- |
| `--trunc-len`       | 3' 端整体截短长度（0 表示不截短）               |
| `--trim-left`       | 5' 端截短碱基数（0 表示不截短）                |
| `--max-ee`          | 最大期望错误数（默认 2）                     |
| `--trunc-q`         | 质量得分截断阈值（默认 2）                    |
| `--min-len`         | 最小保留长度（默认 20）                     |
| `--pool`            | denoise 跨样本合并（`pool=TRUE`）         |
| `--min-overlap`     | mergePairs 最小重叠长度（默认 12）           |
| `--method`          | removeBimera 方法：consensus/pooled/per-sample |
| `--threads`         | 线程数（DADA2 `multithread`）          |

> QIIME 2 等价调用：`qiime dada2 denoise-single/denoise-paired`（QIIME 2 的 DADA2 去噪环节）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。DADA2 以 R 包分发，宿主机既可走 conda，也可用 R/Bioconductor 直装。

### 1. Conda / R（包管理器安装）

```bash
mamba create -n dada2-native -c conda-forge -c bioconda bioconductor-dada2=1.38.0
conda activate dada2-native
```

```bash
# 或用 R / Bioconductor 直装（需 R >= 4.3；Rscript 即为本模块 binary）
Rscript -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("dada2", update=FALSE, ask=FALSE)'
Rscript -e 'cat(as.character(packageVersion("dada2")))'   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（有 Rscript 走 Bioconductor 直装，否则建 bioconda 环境 `bioconductor-dada2=1.38.0`；用法：`bash native/install.sh --help`）。
>
> brew 无公式（2026-09 核实 homebrew-core 与 brewsci/bio 均无 dada2/bioconductor-dada2），故不提供 brew 小节。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0 \
    Rscript -e 'library(dada2); cat(as.character(packageVersion("dada2")), "\n")'
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull dada2.sif docker://depot.galaxyproject.org/singularity/bioconductor-dada2:1.38.0--r45ha27e39d_0
apptainer run dada2.sif Rscript -e 'library(dada2); cat(packageVersion("dada2"), "\n")'
```

## 测试

```bash
bash test/run_test.sh   # R 脚本构造验证为主；Rscript+dada2 可用时追加包加载冒烟
```

## 容器与 Conda 链接

* **官网**：<https://benjjneb.github.io/dada2/>

* **Github仓库**：<https://github.com/benjjneb/dada2>

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/bioconductor-dada2/overview>

* **Docker**：`docker pull quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/bioconductor-dada2%3A1.38.0--r45ha27e39d_0>

* 安装方式（本地）：`mamba create -n dada2 -c conda-forge -c bioconda bioconductor-dada2=1.38.0` 或 `Rscript -e 'BiocManager::install("dada2")'`

## 版本

* dada2 1.38.0（bioconda::bioconductor-dada2=1.38.0，R 包 version 字段）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/bioconductor-dada2 / depot.galaxyproject.org；本地不再自建容器）

* nf-core（modules/nf-core/dada2 404）与 snakemake-wrappers（bio/dada2 404）均无官方模块（2026-09 核实），Nextflow/Snakemake 场景以本模块 native Rscript 驱动为兜底
