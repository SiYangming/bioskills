# snoscan 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 来源：非编码RNA预测教程——snoRNA 预测工具 snoScan / snoGPS。

***

## native 实现

# snoscan / native — 自包含 C/D box snoRNA 预测驱动

snoScAn（命令名 `snoscan`）的本地自包含实现（`source_type: custom`、`type: native`）。

snoScAn 是 Lowe 实验室（UCSC）开发的 **C/D box 甲基化引导 snoRNA** 预测程序（Lowe & Eddy, *Science* 1999；Schattner et al., *NAR* 2005）：给定靶 rRNA 序列与待查序列，搜索同时具备 rRNA 互补区与 C/D box 基序的候选 snoRNA。

## 功能

| 子命令       | 命令                                                                                                   | 作用                            |
| --------- | ---------------------------------------------------------------------------------------------------- | ----------------------------- |
| `search`  | `snoscan [-m <meth>] [-o <out>] [-l N] ... <rRNA.fa> <query.fa>`                                       | 通用 C/D box snoRNA 搜索           |
| `yeast`   | `snoscanY <rRNA.fa> <query.fa>`                                                                        | 酵母（S. cerevisiae）物种预设          |
| `human`   | `snoscanH <rRNA.fa> <query.fa>`                                                                        | 人（H. sapiens）物种预设              |
| `archaea` | `snoscanA <rRNA.fa> <query.fa>`                                                                        | 古菌物种预设                        |
| `sort`    | `sort-snos [-P] [-H] [-R] [-M|-U] [-T N] [-S S] [-m S] [-e E] [-F] <hits>`                             | 对命中做排序 / 过滤 / 去重              |

> 以上命令行依据上行 `snoscan -h`（snoscan 1.0 / 2020-09-04）与 `sort-snos` 无参运行实测输出整理。
> snoScAn 为**单进程**程序，无并行参数；`--threads` 仅记录，不注入命令行。

## 用法

```bash
# CLI 直跑：以酵母 rRNA 为靶，扫描待查序列，输出候选
python main.py search Sc-rRNA.fa query.fa -m Sc-meth.sites -o hits.txt
python main.py yeast  Sc-rRNA.fa query.fa -o hits.yeast.txt
python main.py human  Hu-18S.fa  query.fa  -o hits.human.txt -l 10 -V

# 命中排序 / 过滤
python main.py sort hits.txt -P -S 5 -T 50

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

参数（节选，完整见 `snoscan -h`）：

| 参数          | 说明                                    |
| ----------- | ------------------------------------- |
| 位置 1 / 位置 2 | 靶 rRNA 序列文件 / 待查序列文件（FASTA），缺一不可     |
| `-m`        | 已知甲基化位点文件（配合 `-M` 距离过滤）               |
| `-o`        | 候选命中输出文件                              |
| `-s`        | 同时保存候选 snoRNA 序列                       |
| `-l`        | snoRNA-rRNA 互补区最小长度（默认 9 bp）           |
| `-C` `-D` `-X` `-c` | C box / D′ box / 综合 / 互补区打分阈值          |
| `-d` `-p`   | C/D box 最大间距 / D′ box 存在时的最小间距（默认 10） |
| `-i` `-M` `-V` | 起始扫描位置 / 到已知甲基化位点最大距离 / 详细输出          |

## 实战示例：酵母基因组 C/D box snoRNA 批量扫描

```bash
mkdir -p snoscan_out && cd snoscan_out

# 逐条待查序列扫描（snoscan 每次接收一个 query 文件；多序列可放同一 FASTA 由程序内部遍历）
for i in ../genome_split/*.fa
do
    sample=$(basename "$i" .fa)
    snoscan ../Sc-rRNA.fa "$i" -m ../Sc-meth.sites -o "${sample}.snoscan.out" -M 1000 -V
done

# 汇总命中并排序去重（sort-snos，仅保留对已知甲基化位点的命中）
cat *.snoscan.out > all.hits
sort-snos -P -M -T 50 all.hits > all.hits.sorted
```

> 上述批量用法与 `native/main.py` 的 `search` / `yeast` / `sort` 子命令等价：单条调用走 `main.py search ...`，批量循环时分派到 `search` 与 `sort`（见上「用法」）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n snoscan-native -c conda-forge -c bioconda snoscan=1.0
conda activate snoscan-native
snoscan -h   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap）
brew tap brewsci/bio
brew install brewsci/bio/snoscan
snoscan -h   # 断言
```

> ⚠️ brew 的 `snoscan` 公式当前构建 0.9.1，与 meta 登记 1.0 略有差异（以 formula 为准）。

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `snoscan`，无 conda 时下载官方源码归档 `trna.ucsc.edu/software/snoscan.tar.gz`（0.9.1）编译到 `~/software/snoscan-<ver>` 并写 PATH；默认版本 1.0，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/snoscan:1.0--pl5321h031d066_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/snoscan:1.0--pl5321h031d066_5 snoscan \
    /data/Sc-rRNA.fa /data/query.fa -m /data/Sc-meth.sites -o /data/hits.txt
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull snoscan.sif docker://depot.galaxyproject.org/singularity/snoscan:1.0--pl5321h031d066_5
apptainer run -B $PWD:/data -H /data snoscan.sif snoscan \
    /data/Sc-rRNA.fa /data/query.fa -m /data/Sc-meth.sites -o /data/hits.txt
```

### 4. 官方源码编译（并列保留）

* **官网**：<https://lowelab.ucsc.edu/snoscan/>

* **源码归档**：<https://trna.ucsc.edu/software/snoscan.tar.gz>（snoscan-0.9.1，sha256 `e6ad2f10…8ae19e`）

> 说明：bioconda `snoscan=1.0` 的 source URL（`lowelab.ucsc.edu/software/snoscan-1.0.tar.gz`）2026-09 已 404；官方现存可下载源码归档为 `trna.ucsc.edu` 上的 **0.9.1**。需要 1.0 请走 conda 路线。

```bash
# 下载并解压官方源码
wget https://trna.ucsc.edu/software/snoscan.tar.gz -P ~/software/
tar zxf ~/software/snoscan.tar.gz -C ~/software/
cd ~/software/snoscan-0.9.1

# 编译（先 squid 库，再主程序）
make -C squid-1.5.11
make
export PATH=$PATH:$PWD
snoscan -h   # 断言
```

## 测试

```bash
bash test/run_test.sh   # search/yeast/sort 为 argv 构造验证；snoscan 未安装时跳过真实冒烟
```

## 版本

* snoscan 1.0（bioconda::snoscan=1.0；官方现存源码归档为 0.9.1）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/snoscan / depot.galaxyproject.org；本地不再自建容器）

* nf-core / snakemake-wrappers 均无 snoscan 官方模块（2026-09 核实 404）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/snoscan/overview>

* **Docker**：`docker pull quay.io/biocontainers/snoscan:1.0--pl5321h031d066_5`

* **Singularity**：<https://depot.galaxyproject.org/singularity/snoscan%3A1.0--pl5321h031d066_5>

* 安装方式（本地）：`mamba create -n snoscan -c conda-forge -c bioconda snoscan=1.0`
