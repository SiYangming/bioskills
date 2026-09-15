# soapdenovo2 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 soapdenovo2 子模块（2026-09 抓取 404），故本模块只提供 `native/` 实现。

***

## native 实现

# soapdenovo2 / native — 自包含短读组装驱动

SOAPdenovo2 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

五个子命令对应 SOAPdenovo2 的组装链路（`--mer 63|127` 选择 `SOAPdenovo-63mer` / `SOAPdenovo-127mer`）：

| 子命令        | 命令                                                                                | 作用                              |
| ---------- | --------------------------------------------------------------------------------- | ------------------------------- |
| `all`      | `SOAPdenovo-63mer all -s <config> -o <prefix> -K 51 -p N [-R]`                     | 一步式 pregraph→contig→map→scaff    |
| `pregraph` | `SOAPdenovo-63mer pregraph -s <config> -o <prefix> -K 51 -p N [-R]`                | 构建 de Bruijn 图                  |
| `contig`   | `SOAPdenovo-63mer contig -g <prefix> [-R]`                                         | 由图构建 contig                     |
| `map`      | `SOAPdenovo-63mer map -s <config> -g <prefix>`                                     | 将 reads 比对回 contig              |
| `scaff`    | `SOAPdenovo-63mer scaff -g <prefix> [-F]`                                          | 利用配对信息构建 scaffold               |

## 用法

```bash
# CLI 直跑（一步式组装，仿文档示例：-K 51 -p 4 -R）
python main.py all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R

# 分步组装
python main.py pregraph -s config.txt -o out_K51/E_coli -K 51 -p 8 -R
python main.py contig -g out_K51/E_coli -R
python main.py map -s config.txt -g out_K51/E_coli
python main.py scaff -g out_K51/E_coli -F

# 大 k-mer 数据改用 127mer
python main.py all -s config.txt -o out_K127/E_coli -K 127 --mer 127

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例

SOAPdenovo2 基于 De Bruijn Graph，专门处理 Illumina paired-end 与 mate-pair 数据。以下为文档给出的完整批量用法；等价能力由 `native/main.py` 的 `all`（或分步 `pregraph`/`contig`/`map`/`scaff`）子命令提供。

```bash
mkdir -p 04.genome_assembling/SOAPdenovo
cd 04.genome_assembling/SOAPdenovo

# 建立数据符号链接（BLESS 纠错后的 reads）
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.1.corrected.fastq jumping.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.2.corrected.fastq jumping.2.fastq

# 创建配置文件 config.txt（max_rd_len + 两个 [LIB]：fragment / jumping）
cat > config.txt <<'EOF'
max_rd_len=101
[LIB]
avg_ins=177
reverse_seq=0
asm_flags=1
rd_len_cutoff=100
rank=1
pair_num_cutoff=3
map_len=32
q1=/path/to/fragment.1.fastq
q2=/path/to/fragment.2.fastq
[LIB]
avg_ins=3000
reverse_seq=1
asm_flags=2
rd_len_cutoff=63
rank=2
pair_num_cutoff=5
map_len=35
q1=/path/to/jumping.1.fastq
q2=/path/to/jumping.2.fastq
EOF

# 运行组装
mkdir out_K51
SOAPdenovo-63mer all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R &> soapdenovo.log

# 结果统计（*.scafSeq 即最终 scaffold 序列）
grep -c '^>' out_K51/E_coli.scafSeq
```

> 桥接句：`SOAPdenovo-63mer all ...` 等价能力由 `native/main.py` 的 `all` 子命令提供（`python main.py all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R`）。

### 参数说明

| 参数           | 说明                          |
| ------------ | --------------------------- |
| `-K 51`      | k-mer 长度（必须为奇数；63mer 上限 63，127mer 上限 127） |
| `-p 4`       | 线程数                         |
| `-R`         | 使用 read 重新构建（解决重复）           |
| `-F`         | scaffold 阶段填补 gap           |
| `-s config.txt` | 配置文件路径                      |
| `-o`         | 输出前缀                        |

### 配置文件参数说明

| 参数                | 说明                              |
| ----------------- | ------------------------------- |
| `max_rd_len`      | 最大 read 长度（全局段）                 |
| `avg_ins`         | 插入片段平均长度                        |
| `reverse_seq`     | 是否反向互补（mate-pair 数据为 1）          |
| `asm_flags`       | 组装类型（1: paired-end, 2: mate-pair） |
| `rank`            | 文库优先级                           |
| `pair_num_cutoff` | 支持 scaffold 连接的最小配对数            |
| `map_len`         | 最小比对长度                          |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda（包管理器安装）

```bash
mamba create -n soapdenovo2-native -c conda-forge -c bioconda soapdenovo2=2.40
conda activate soapdenovo2-native
which SOAPdenovo-63mer SOAPdenovo-127mer   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `soapdenovo2`；无 conda 时自动下载官方源码 r241 编译到 `~/software/soapdenovo2-r241` 并写 PATH。**注意版本差异**：bioconda/容器为 2.40（源码 r240），`--method source` 构建文档所用 r241。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/soapdenovo2:2.40--1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/soapdenovo2:2.40--1 \
    SOAPdenovo-63mer all -s config.txt -o out_K51/E_coli -K 51 -p 4 -R
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull soapdenovo2.sif docker://depot.galaxyproject.org/singularity/soapdenovo2:2.40--1
apptainer run -B $PWD:/data -H /data soapdenovo2.sif \
    SOAPdenovo-63mer all -s /data/config.txt -o /data/out_K51/E_coli -K 51 -p 4 -R
```

### 4. 官方源码编译（无官方预编译二进制资产）

2026-09 核实：GitHub release r241 **无预编译产物**（release assets 为空），官方仅分发源码，需自行 `make` 编译。文档所用版本即为 r241（仓库 `VERSION` = `2.04-r241`）：

```bash
wget https://github.com/aquaskyline/SOAPdenovo2/archive/r241.tar.gz -O ~/software/SOAPdenovo2-r241.tar.gz
mkdir -p ~/software
tar zxf ~/software/SOAPdenovo2-r241.tar.gz -C ~/software/
cd ~/software/SOAPdenovo2-r241
make                       # 生成 SOAPdenovo-63mer / SOAPdenovo-127mer / SOAPdenovo-fusion
export PATH=$PATH:~/software/SOAPdenovo2-r241/
SOAPdenovo-63mer           # 输出用法即安装成功（无 --version 选项）

# 编译依赖：g++（Linux 下还需 libbam/htslib 提供 -lbam，见仓库 Makefile）
```

> 💡 说明：`make` 后三个可执行文件在源码根目录；也可 `bash native/install.sh --method source` 一键完成（含 `make install` 到用户前缀与 PATH 写入）。

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（组装需真实 reads）
```

## 版本

* soapdenovo2 2.40（bioconda::soapdenovo2=2.40 / 容器 tag `2.40--1`；源码基线 r240）
* 文档源码版本：GitHub release **r241**（`VERSION` = `2.04-r241`，2017-01-03；无预编译资产）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/soapdenovo2 / depot.galaxyproject.org；本地不再自建容器）
* ⚠️ 文档「SOAPdenovo2 暂无官方 conda 包」的说法不成立：bioconda 有 `soapdenovo2=2.40`（源码 r240）。若需精确复现文档 r241，请走官方源码编译。

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/soapdenovo2/overview>
* **Docker**：`docker pull quay.io/biocontainers/soapdenovo2:2.40--1`（另有 `2.40--0`）
* **Singularity**：<https://depot.galaxyproject.org/singularity/soapdenovo2%3A2.40--1>
* **GitHub**：<https://github.com/aquaskyline/SOAPdenovo2>（releases：r240 / r241 / r242）
* 安装方式（本地）：`mamba create -n soapdenovo2 -c conda-forge -c bioconda soapdenovo2=2.40`
