# genewise 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方「环境安装」，容器与 conda 信息记录于文末。
> 本模块仅登记 native 实现（官方 nf-core / snakemake-wrappers 均无 genewise，见文末「官方实现登记」）。

***

## native 实现

# genewise / native — 自包含同源蛋白辅助基因预测驱动

GeneWise（wise2）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

GeneWise 是一个利用同源蛋白序列来预测基因结构的工具。

三个子命令覆盖同源蛋白预测链路：

| 子命令        | 命令                                                                                                     | 作用                              |
| ---------- | ------------------------------------------------------------------------------------------------------ | ------------------------------- |
| `genewise` | `genewise [-gff] <protein> <dna>`                                                                      | 单条同源蛋白→DNA 基因结构预测（`-gff` 出 GFF） |
| `homolog`  | `homolog_genewise --cpu N [--coverage_ratio R] [--evalue E] [--max_gene_length L] <protein.fasta> <genome.fasta>` | 全基因组并行预测（封装脚本）                  |
| `gff2gff3` | `homolog_genewiseGFF2GFF3 --genome <genome> [--min_score S] [--gene_prefix P] <genewise.gff>`          | GFF→GFF3 转换并按得分过滤                |

> ⚠️ 封装脚本 `homolog_genewise` / `homolog_genewiseGFF2GFF3` 由 **GETA** 仓库（<https://github.com/chenlianfu/geta> 的 `bin/`，2026-09-11 核实存在）提供，不在 wise2 源码包内；使用 `genewise` 子命令只需 wise2，使用 `homolog` / `gff2gff3` 子命令需另装 GETA。

## 用法

```bash
# CLI 直跑
python main.py genewise -gff homolog.fasta region.fasta -o gene.gff
python main.py homolog --coverage_ratio 0.4 --evalue 1e-9 --max_gene_length 2000 --threads 8 homolog.fasta genome.fasta
python main.py gff2gff3 --genome genome.fasta --min_score 15 --gene_prefix genewise genewise.gff -o genewise.gff3

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`homolog` 注入 `--cpu N`）。

## 实战示例：同源蛋白辅助基因预测（genewise）

GeneWise 利用同源蛋白序列预测基因结构。直接使用 `genewise` 无法做全基因组水平预测，需配合封装脚本 `homolog_genewise`；预测结果再用 `homolog_genewiseGFF2GFF3` 转 GFF3 并按得分过滤（去除含终止密码子的基因）。以下为教学文档（docs/10.md 第三节）典型用法；等价能力由 `native/main.py` 的 `genewise` / `homolog` / `gff2gff3` 子命令提供（见上「用法」）。

```bash
mkdir -p homolog && cd homolog

# 1) 准备输入：hardmask 后的基因组 + 同源蛋白（去描述、点号转下划线）
ln -s ../genome.hardmaskN.fasta genome.fasta
gzip -dc ../GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta

# 2) 用 genewise 通过同源蛋白对基因组做基因结构注释（封装脚本并行）
homolog_genewise --cpu 8 --coverage_ratio 0.4 --evalue 1e-9 --max_gene_length 2000 homolog.fasta genome.fasta

# 3) 转 GFF3 并按得分过滤
homolog_genewiseGFF2GFF3 --genome genome.fasta --min_score 15 --gene_prefix genewise genewise.gff \
    > genewise.gff3 2> gene_id.with_stop_codon.list
```

| 参数                      | 说明                          |
| ----------------------- | --------------------------- |
| `--cpu 8`               | 并行线程数（`homolog`）            |
| `--coverage_ratio 0.4`  | 覆盖度阈值（`homolog`）             |
| `--evalue 1e-9`         | E-value 阈值（`homolog`）        |
| `--max_gene_length 2000` | 最大基因长度（`homolog`）           |
| `--min_score 15`        | 最小得分阈值（`gff2gff3`）          |

> 直接使用 genewise 无法进行全基因组水平的基因预测，需要使用封装脚本
>
> 注意事项：推荐使用 hardmask 重复序列后的基因组；预测结果需过滤（如去除含有终止密码子的基因）。
>
> 预测结果需要进行过滤处理（如去除含有终止密码子的基因）

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda wise2 → quay.io/biocontainers → depot.galaxyproject.org 预构建 sif），直接拉取官方镜像/conda 安装 `genewise`；main.py 驱动在宿主机跑。官方另有源码编译路线（wise2 源码，含 glibc/getline 兼容修补），并列保留如下 §4。

### 1. Conda / brew（包管理器安装，备选）

```bash
mamba create -n genewise-native -c conda-forge -c bioconda wise2=2.4.1
conda activate genewise-native
genewise -version   # 断言
```

> 说明：brew（homebrew-core / brewsci-bio）**无 genewise / wise2 公式**（2026-09-11 核实 404），故不登记 brew 安装块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `genewise`，无 conda 时走官方源码编译并写 PATH/WISECONFIGDIR；版本默认 2.4.1，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/wise2:2.4.1--h17e8430_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/wise2:2.4.1--h17e8430_6 \
    genewise -gff homolog.fasta region.fasta
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull genewise.sif docker://depot.galaxyproject.org/singularity/wise2:2.4.1--h17e8430_6
apptainer run -B $PWD:/data -H /data genewise.sif \
    genewise -gff /data/homolog.fasta /data/region.fasta
```

### 4. 官方源码编译（并列保留；含 glibc/getline 兼容修补）

```bash
# 官方源码（EBI Birney lab）
curl -fSL -o wise2.4.1.tar.gz https://www.ebi.ac.uk/~birney/wise2.4.1.tar.gz
tar zxf wise2.4.1.tar.gz -C ~/software/
cd ~/software/wise2.4.1/src/

# 兼容修补glib-config → pkg-config
find ./ -name makefile | xargs sed -i 's/glib-config/pkg-config --libs glib-2.0/'
# getline 与新版 glibc 冲突 → get_line；isnumber 非标准 → isdigit
perl -p -i -e 's/getline/get_line/g' ./HMMer2/sqio.c
perl -p -i -e 's/isnumber/isdigit/' models/phasemodel.c

make all -j 4
export WISECONFIGDIR=~/software/wise2.4.1/wisecfg/
echo 'export PATH=$PATH:~/software/wise2.4.1/src/bin/' >> ~/.bashrc
echo 'export WISECONFIGDIR=~/software/wise2.4.1/wisecfg/' >> ~/.bashrc
source ~/.bashrc
genewise -version
```

> 依赖提示：源码编译需 `make` + C 编译器 + glib（`pkg-config --libs glib-2.0`）+ perl；Debian 系可 `apt-get install -y --no-install-recommends build-essential pkg-config libglib2.0-dev perl`。

## 官方实现登记（nf-core / snakemake-wrappers）

* **nf-core**：`modules/nf-core/genewise`（及 `wise2`）不存在（2026-09-11 核实 404）→ 未建立 nextflow 说明层，Nextflow 场景请以本模块 `native/` 为兜底。
* **snakemake-wrappers**：`bio/genewise`（及 `bio/wise2`）不存在（2026-09-11 核实 404）→ 未建立 snakemake 说明层，Snakemake 场景请以本模块 `native/` 为兜底。

## 测试

```bash
bash test/run_test.sh   # genewise/homolog/gff2gff3 退化为 argv 构造验证（不依赖已安装 genewise）
```

## 版本

* GeneWise 2.4.1（wise2 2.4.1；bioconda::wise2=2.4.1，容器 tag `2.4.1--h17e8430_6`）
* 构建路线：官方镜像/conda 优先（quay.io/biocontainers/wise2 / depot.galaxyproject.org；本地不再自建容器）；官方源码编译（含 glibc/getline 修补）并列保留
* 封装脚本 `homolog_genewise` / `homolog_genewiseGFF2GFF3` 由 GETA 提供（非 wise2 自带）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/wise2/overview>
* **Docker**：`docker pull quay.io/biocontainers/wise2:2.4.1--h17e8430_6`
* **Singularity**：<https://depot.galaxyproject.org/singularity/wise2:2.4.1--h17e8430_6>
* **在线工具**：https://www.ebi.ac.uk/jdispatcher/psa/genewise
* **下载**：https://www.ebi.ac.uk/~birney/wise2/
* **官方源码**：<https://www.ebi.ac.uk/~birney/wise2/wise2.4.1.tar.gz>
* 安装方式（本地）：`mamba create -n genewise -c conda-forge -c bioconda wise2=2.4.1`
