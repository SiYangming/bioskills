# circos 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# circos / native — 自包含环形图渲染驱动

Circos 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

Circos 是一款强大的基因组环形图（Circular Plot）绘制工具，由加拿大科学家 Martin Krzywinski 开发，专门用于可视化基因组数据。它能够以环形方式展示染色体特征分布、基因表达、共线性关系、SNP 密度等复杂数据，是基因组学研究中最常用的可视化工具之一。

| 子命令       | 命令                                                        | 作用                              |
| --------- | --------------------------------------------------------- | ------------------------------- |
| `plot`    | `circos -noparanoid -conf <circos.conf> [-outputdir <dir>]` | 依配置渲染环形图（PNG/SVG）                |
| `modules` | `circos -modules`                                          | 检查 Circos 依赖的 Perl 模块是否齐全       |
| `gddiag`  | `gddiag`                                                   | GD 渲染依赖诊断（生成 gddiag.png）         |

## 用法

```bash
# CLI 直跑
python main.py plot -conf circos.conf -outputdir out
python main.py modules
python main.py gddiag

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（Circos 为单进程 Perl 渲染，`--threads` 仅作契约字段保留）。

## 实战示例：染色体组型 + GC/SNP 直方图 + 共线性 links

以下为典型用法；等价能力由 `native/main.py` 的 `plot` 子命令提供（命令装配见上「用法」）。

### 1. 环境自检

```bash
circos -modules   # 检查依赖模块是否全部安装
gddiag            # 测试 GD 渲染
circos --help
```

### 2. 运行官方示例（先验证环境）

```bash
cd /opt/biosoft/circos-0.69-6/example/
../bin/circos -conf etc/circos.conf
```

### 3. 准备数据文件

```bash
mkdir -p ~/12.genome_visualization/circos && cd ~/12.genome_visualization/circos
ln -s ~/assemblies_of_Malassezia_sympodialis/genome.fasta ./
ln -s ~/Malassezia_sympodialis_V01.GeneModels.gff3 genome.gff3
```

### 4. 生成染色体组型 / GC / SNP 直方图 / 表达量热图

```bash
# 染色体组型（Karyotype）
circos_create_karyotype_by_genome.pl genome.fasta > karyotype.txt

# GC 含量直方图
circos_create_gc_histogram.pl genome.fasta 10000 > gc.histogram.txt

# SNP 密度直方图
VCF_get_variants_density_for_circos.pl variants.vcf genome.fasta > variant_density.histogram_for_circos.txt

# 基因表达量热图
cut -f 1,2,5 gene.TPM.TMM.matrix > gene.TPM.TMM.matrix.cut
circos_create_expression_heatmap.pl gene.TPM.TMM.matrix.cut genome.gff3 > gene_expression.heatmap.txt
```

### 5. 基因组比对 links（共线性，需 makeblastdb/blastn）

```bash
makeblastdb -in genome.fasta -dbtype nucl -title genome -parse_seqids -out genome
blastn -query genome.fasta -db genome -out blast.out -evalue 1e-5 -outfmt 6 -num_threads 8
perl -e 'while (<>) { @_ = split /\t/; print if $_[6] ne $_[8] && $_[2] >= 90 && $_[3] >= 1000 }' blast.out \
    | sort -k 1.13n -k 7n > similarity.txt
```

### 6. 渲染

```bash
cp ~/data_for_circos/*.conf ./
circos -noparanoid -conf circos.conf
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n circos-native -c conda-forge -c bioconda circos=0.69.6
conda activate circos-native
circos -modules   # 断言 + 依赖检查
```

```bash
# 或用 Homebrew（brewsci/bio tap；homebrew-core 无 circos）
brew tap brewsci/bio
brew install circos
circos -modules
```

> brew（brewsci/bio）当前版本与 meta 登记的 0.69.6 可能略有差异，以 formula 为准。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/circos:0.69.6--pl5.22.0_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/circos:0.69.6--pl5.22.0_0 \
    circos -noparanoid -conf circos.conf
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull circos.sif docker://depot.galaxyproject.org/singularity/circos:0.69.6--pl5.22.0_0
apptainer exec -B $PWD:/data circos.sif circos -noparanoid -conf /data/circos.conf
```

### 4. 官方源码 tarball（无 conda / docker 依赖）

Circos 官方以 Perl 源码 tarball 分发（无预编译二进制）；解压后将 `bin` 加入 PATH，依赖模块用 `circos -modules` 检查后按缺失项补装：

```bash
wget http://circos.ca/distribution/circos-0.69-6.tgz -P ~/software/
tar zxf ~/software/circos-0.69-6.tgz -C ~/software/
# 检查并安装缺失的 Perl 模块
~/software/circos-0.69-6/bin/circos -modules \
    | perl -ne 'print "$1 " if m/missing\s+(\S+)/' \
    | perl -pe 's/^/cpan -i /; s/$/\n/' | sh
echo 'export PATH=$PATH:~/software/circos-0.69-6/bin/' >> ~/.bashrc
source ~/.bashrc
circos -modules
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `circos`，无 conda 时下载官方 tarball 到 `~/software/circos-<ver>` 并写 PATH；用法：`bash native/install.sh --help`）。

## 测试

```bash
bash test/run_test.sh   # circos 未安装时退化为 argv 构造验证；已安装则真实渲染最小环形图
```

## 版本

* circos 0.69.6（官方 tarball circos-0.69-6.tgz；bioconda::circos=0.69.6）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/circos / depot.galaxyproject.org；本地不再自建容器）

* 官方 nf-core modules 无 circos、snakemake-wrappers 无 bio/circos（均为 404），无官方流程实现登记

## 容器与 Conda 链接

* **官网**：http://circos.ca/

* **下载**：http://circos.ca/software/download/

* **文档**：http://circos.ca/documentation/

* **教程**：http://circos.ca/tutorials/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/circos/overview>

* **Docker**：`docker pull quay.io/biocontainers/circos:0.69.6--pl5.22.0_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/circos%3A0.69.6--pl5.22.0_0>

* 安装方式（本地）：`mamba create -n circos -c conda-forge -c bioconda circos=0.69.6`
