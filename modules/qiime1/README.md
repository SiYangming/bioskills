# qiime1 软件模块（QIIME 1.9.1 — 第一代微生物组分析工具包）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **QIIME 1（Quantitative Insights Into Microbial Ecology 1，1.9.1）** 基于 **Python 2.7**，用 **OTU 聚类**
> 方法完成从原始测序数据到多样性分析的完整流程，是第一代微生物组分析工具包。上游 **2018 年停止维护**，
> Python 2.7 已于 2020-01 EOL。
>
> **新项目请勿使用**——OTU 工作流已被 **QIIME 2**（DADA2/Deblur ASV 工作流，见本仓库 `qiime2` 模块）取代。
> 本模块只做「录入」：方法/命令/链接准确登记、**不产出自建容器配方**（Dockerfile/Apptainer.def），
> 仅供复现历史 QIIME 1 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按 QIIME1各脚本参数构造历史命令行并打印，
**不实际执行**（软件 deprecated、Py2.7 EOL）。覆盖 15 个常用脚本：

| 子命令 | 脚本 | 作用 |
| ---- | ---- | ---- |
| `validate_mapping_file` | `validate_mapping_file.py` | 校验 mapping 文件 |
| `join_paired_ends` | `join_paired_ends.py` | 双端序列拼接（fastq-join） |
| `split_libraries_fastq` | `split_libraries_fastq.py` | 拆分样本 / demultiplexing |
| `pick_open_reference_otus` | `pick_open_reference_otus.py` | 开放式参考 OTU 挑选（支持 `-O` 并行） |
| `parallel_identify_chimeric_seqs` | `parallel_identify_chimeric_seqs.py` | 并行嵌合体鉴定（支持 `-O` 并行） |
| `filter_fasta` | `filter_fasta.py` | 按序列 id 过滤 FASTA |
| `make_otu_table` | `make_otu_table.py` | 构建 OTU 表（BIOM） |
| `filter_alignment` | `filter_alignment.py` | 过滤比对结果 |
| `make_phylogeny` | `make_phylogeny.py` | 构建系统发育树 |
| `summarize_taxa_through_plots` | `summarize_taxa_through_plots.py` | 物种分类统计与可视化 |
| `beta_diversity_through_plots` | `beta_diversity_through_plots.py` | Beta 多样性分析 |
| `alpha_rarefaction` | `alpha_rarefaction.py` | Alpha 多样性稀释分析 |
| `print_qiime_config` | `print_qiime_config.py` | 打印 QIIME 配置与依赖自检（`-tf`） |
| `assign_taxonomy` | `assign_taxonomy.py` | 物种分类注释（rdp/uclust/blast） |
| `pick_otus` | `pick_otus.py` | OTU 挑选（uclust） |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 QIIME 1.9.1，见「环境安装」）
python main.py validate_mapping_file -m mapping.txt -o 01.mapping_file_output
python main.py join_paired_ends -f R1.fastq.gz -r R2.fastq.gz -o 02.join_paired_ends/F3D0
python main.py pick_open_reference_otus -i seqs.fna -p parameters_otu.txt -o 04.pick_open_reference_otus -a --threads 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（仅对支持 `-O` 的脚本注入）与 `--tmpdir`。构造命令通过 stderr 打印
deprecated 提示，stdout 只输出命令本身。

### 历史流程

QIIME 1（Quantitative Insights Into Microbial Ecology 1）是第一代微生物组分析工具包，基于 Python 2.7 开发，采用 OTU（Operational Taxonomic Unit）聚类方法进行群落分析。它提供了从原始测序数据到多样性分析的完整流程，是微生物组领域的经典工具。

映射校验 → 双端拼接 → 拆样 → 开放式参考 OTU → 嵌合体检测/过滤 → OTU 表 → 系统发育 → 物种组成/多样性：

```bash
validate_mapping_file.py -m 00.qiime_data/mapping.txt -o 01.mapping_file_output
join_paired_ends.py -f R1.fastq.gz -r R2.fastq.gz -o 02.join_paired_ends/F3D0
split_libraries_fastq.py -i 02.join_paired_ends/*/fastqjoin.join.fastq -o 03.split_libraries_fastq \
    -m 00.qiime_data/mapping.txt -q 19 -p 0.75 --barcode_type 'not-barcoded'
pick_open_reference_otus.py -i 03.split_libraries_fastq/seqs.fna -p parameters_otu.txt -o 04.pick_open_reference_otus -a -O 4
parallel_identify_chimeric_seqs.py -i rep_set_aligned_pfiltered.fasta -t 97_otu_taxonomy.txt -r 97_otus.fasta -m blast_fragments -o chimeric_seqs.txt -O 4
filter_fasta.py -f rep_set_aligned_pfiltered.fasta -s chimeric_seqs.txt -n -o non_chimeric_rep_set.fasta
make_otu_table.py -i final_otu_map_mc2.txt -t rep_set_tax_assignments.txt -e chimeric_seqs.txt -o non_chimeric_otu_table.biom
filter_alignment.py -i non_chimeric_rep_set.fasta -m lanemask_in_1s_and_0s -o pynast_aligned_seqs/
make_phylogeny.py -i non_chimeric_rep_set_pfiltered.fasta -o non_chimeric_rep_set.tre
summarize_taxa_through_plots.py -i non_chimeric_otu_table.biom -m mapping.txt -o 06.summarize_taxa
beta_diversity_through_plots.py -i non_chimeric_otu_table.biom -m mapping.txt -t non_chimeric_rep_set.tre -e 2797 -p betaParams.txt -o 07.beta_diversity
alpha_rarefaction.py -i non_chimeric_otu_table.biom -m mapping.txt -p alphaParams.txt -t non_chimeric_rep_set.tre -o 08.alpha_diversity
```

> 等价能力由 `native/main.py` 的同名子命令提供（见上「用法」）；先 CLI 后 main.py。

## 测试

```bash
bash test/run_test.sh   # 命令构造/线程注入/parser/CLI stub 自省为常驻断言（不下载/不执行真实分析）
```

## 环境安装（历史渠道登记；deprecated 不维护本地配方）

> 官方现状（2026-09 核实，如实记录）：上游 2018 停更、Py2.7 EOL。历史渠道仍可复现：
> bioconda **qiime=1.9.1** → quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建历史镜像；
> 另有 Py2.7 下 `pip2.7 install qiime` 与官方 `qiime-deploy` 部署工具。软件 deprecated → **不维护本地
> Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 qiime=1.9.1（linux-64/osx-64）
mamba create -n qiime1-native -c conda-forge -c bioconda qiime=1.9.1
conda activate qiime1-native
print_qiime_config.py -tf   # 断言：打印配置；failures 可按提示补装依赖
```

> 一键安装也可运行 `native/install.sh`（有 conda/mamba 建 bioconda `qiime=1.9.1` 环境；无 conda 回退
> 历史 pip2.7 路线）。
>
> Homebrew：homebrew-core（`formulae.brew.sh/api/formula/qiime.json`）与 brewsci/bio（`Formula/qiime.rb`）
> 均 404（2026-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（历史镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 1.9.1 老包自动构建）：

```bash
docker pull quay.io/biocontainers/qiime:1.9.1--py27_0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/qiime:1.9.1--py27_0 \
    pick_open_reference_otus.py -i /data/seqs.fna -o /data/out -a -O 4
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09 核实存在，与 quay tag 互通）：

```bash
apptainer pull qiime.sif docker://depot.galaxyproject.org/singularity/qiime:1.9.1--py27_0
apptainer run -B $PWD:/data -H /data qiime.sif \
    validate_mapping_file.py -m /data/mapping.txt -o /data/01.mapping_file_output
```

### 4. 源码 / pip2.7 / qiime-deploy（历史路线）

```bash
# Python 2.7 下 pip 安装（需自备 Py2.7，见 01.md）
/opt/sysoft/Python-2.7.11/bin/pip2.7 install qiime

# 官方部署工具 qiime-deploy（历史）
git clone https://github.com/qiime/qiime-deploy.git
git clone https://github.com/qiime/qiime-deploy-conf.git
cd qiime-deploy/
python qiime-deploy.py <deploy_dir> -f ../qiime-deploy-conf/qiime-1.9.1/qiime.conf --force-remove-failed-dirs
```

## 替代建议（新项目请直接使用）

| 替代 | 说明 | 入口 |
| ---- | ---- | ---- |
| **QIIME 2** | 下一代平台，Artifact（QZA/QZV）+ DADA2/Deblur ASV 工作流 | 本仓库 `qiime2` 模块 / <https://qiime2.org/> |

## 版本

**官网**：http://qiime.org/

* QIIME **1.9.1**（生物信息组经典流程；bioconda latest=1.9.1，PyPI qiime 1.9.1 license=GPL）
* License：**GPL-2.0**（bioconda/PyPI 登记 GPL；上游 2018 停更）
* 历史容器：`quay.io/biocontainers/qiime:1.9.1--py27_0` / depot sif（自动构建历史镜像）
* nf-core / snakemake-wrappers：无官方子模块（2026-09 核实 `modules/nf-core/qiime`、`bio/qiime` 均 404）→ 不登记官方说明层
