# quickmerge 软件模块

> 汇总说明：本 README 合并 native 实现用法；安装方式见下方各节，容器与 conda 信息记录于此。
>
> **依赖提示**：quickmerge 依赖 MUMmer 的 `nucmer` / `delta-filter`（官方 conda 包 `quickmerge=0.3`
> 会**自动包含** MUMmer 依赖）；MUMmer 本身见 `modules/mummer`。

***

## native 实现

# quickmerge / native — 自包含 metassembler 驱动

quickmerge 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

quickmerge 是一个用于整合多个基因组组装结果的工具，能够合并不同组装工具生成的序列，提高组装质量。

四个子命令对应文档 quickmerge 的完整链路（比对 → 过滤 → 合并）：

| 子命令            | 命令                                                                                                       | 作用                            |
| -------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `nucmer`       | `nucmer [--threads N] [-p out] [-c 200] <ref> <qry>`                                                      | MUMmer 比对 → `out.delta`          |
| `para_nucmer`  | `para_nucmer --CPU N --nucmer " <opts>" <ref> <qry>`                                                      | MUMmer 并行比对 → `out.delta`（stdout） |
| `delta_filter` | `delta-filter [-i 95] [-r] [-q] <delta>`                                                                  | 过滤 delta → `out.rq.delta`（stdout） |
| `quickmerge`   | `quickmerge -d <delta> -q <qry> -r <ref> [-hco 5.0] [-c 1.5] [-l 100000] [-ml 5000] [-p out]`             | 合并组装 → `<prefix>_out.fasta`       |

> 写 stdout 的子命令（`para_nucmer` / `delta_filter`）提供 `-o/--output` 时由驱动把 stdout 落盘。

## 用法

```bash
# CLI 直跑
python main.py para_nucmer ref.fasta qry.fasta --CPU 8 --nucmer-args " -p out -l 100" -o out.delta
python main.py delta_filter out.delta -i 95 -r -q -o out.rq.delta
python main.py quickmerge -d out.rq.delta -q qry.fasta -r ref.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`nucmer` 注入 `--threads`、`para_nucmer` 注入 `--CPU`）/ `--tmpdir` 运行期覆盖。

## 实战示例：quickmerge 合并两个组装

```bash
mkdir -p quickmerge && cd quickmerge
ln -s ~/04.genome_assembling/DBG2OLC/DBG2OLC.fasta ./
ln -s ~/04.genome_assembling/Canu/Malassezia_sympodialis/Canu.fasta ./

# 方式一：以 DBG2OLC 为参考，Canu 为查询
mkdir DBG2OLC_Canu && cd DBG2OLC_Canu
# --CPU 8: 使用 8 个线程；--nucmer " -p out -l 100": nucmer 参数（输出前缀、最小匹配长度）
para_nucmer --CPU 8 --nucmer " -p out -l 100" ../DBG2OLC.fasta ../Canu.fasta > out.delta
# -i 95: 最小相似度 95%；-r: 参考序列过滤；-q: 查询序列过滤
delta-filter -i 95 -r -q out.delta > out.rq.delta
quickmerge -d out.rq.delta -q ../Canu.fasta -r ../DBG2OLC.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out
cd ..

# 方式二：以 Canu 为参考，DBG2OLC 为查询
mkdir Canu_DBG2OLC && cd Canu_DBG2OLC
para_nucmer --CPU 8 --nucmer " -p out -l 100" ../Canu.fasta ../DBG2OLC.fasta > out.delta
delta-filter -i 95 -r -q out.delta > out.rq.delta
quickmerge -d out.rq.delta -q ../DBG2OLC.fasta -r ../Canu.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p out

# 格式化结果
genome_seq_clear.pl --seq_prefix quickmerge Canu_DBG2OLC/merged_out.fasta > quickmerge.fasta
```

等价能力由 `native/main.py` 的 `nucmer` / `para_nucmer` / `delta_filter` / `quickmerge` 子命令提供（见上「用法」）。

### 参数说明

| 参数           | 说明                          |
| ------------ | --------------------------- |
| `-d`         | 过滤后的 delta 文件（`out.rq.delta`） |
| `-q`         | 查询组装 FASTA                   |
| `-r`         | 参考组装 FASTA                   |
| `-hco`       | 同源性截止值（默认 5.0，文档示例 5.0）    |
| `-c`         | 覆盖度阈值（默认 1.5，文档示例 1.5）      |
| `-l`         | 最小序列长度（默认 100000）           |
| `-ml`        | 最小重叠长度（默认 5000）             |
| `-p`         | 输出前缀（→ `<prefix>_out.fasta`） |
| `-i`/`-r`/`-q` | delta-filter：最小相似度 / 参考 / 查询最佳匹配 |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
`main.py` 驱动在宿主机跑。官方 release **仅提供源码归档**（v0.3 无预编译二进制资产，2026-09 核实）。

### 1. Conda / brew（包管理器安装）

```bash
# conda 安装自动包含 MUMmer 依赖
mamba create -n quickmerge -c conda-forge -c bioconda quickmerge=0.3
conda activate quickmerge
quickmerge -h   # 断言（quickmerge 无 --version）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install quickmerge
quickmerge -h            # 断言（brew 公式为 v0.3，与 meta 一致；依赖 brewsci/bio/mummer）
```

> 一键安装直接 `bash native/install.sh`（默认 auto：有 conda/mamba 走 bioconda `quickmerge=0.3`，无 conda 时回退官方源码 `make_merger.sh`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/quickmerge:0.3--pl5321h503566f_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/quickmerge:0.3--pl5321h503566f_6 \
    quickmerge -d /data/out.rq.delta -q /data/Canu.fasta -r /data/DBG2OLC.fasta \
    -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p /data/out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull quickmerge.sif docker://depot.galaxyproject.org/singularity/quickmerge:0.3--pl5321h503566f_6
apptainer run -B $PWD:/data -H /data quickmerge.sif \
    quickmerge -d /data/out.rq.delta -q /data/Canu.fasta -r /data/DBG2OLC.fasta -hco 5.0 -c 1.5 -l 100000 -ml 5000 -p /data/out
```

### 4. 官方源码编译（并列保留）

```bash
wget https://github.com/mahulchak/quickmerge/archive/v0.3.tar.gz -O ~/software/quickmerge-0.3.tar.gz
tar zxf ~/software/quickmerge-0.3.tar.gz -C ~/software/
cd ~/software/quickmerge-0.3
bash make_merger.sh
echo 'export PATH=$PATH:~/software/quickmerge-0.3/merger' >> ~/.bashrc && source ~/.bashrc
quickmerge -h   # 断言
```

> 一键安装：`bash native/install.sh --method source`（clone tag v0.3 → `make_merger.sh` → 安装
> `merger/quickmerge` 到 `~/software/quickmerge-0.3/bin` 并写 PATH；需自行安装 MUMmer）。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（四子命令）+ 自省；二分制未安装时跳过真实冒烟
```

## 容器与 Conda 链接

* **Github**：https://github.com/mahulchak/quickmerge

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/quickmerge/overview>

* **Docker**：`docker pull quay.io/biocontainers/quickmerge:0.3--pl5321h503566f_6`

* **Singularity**：<https://depot.galaxyproject.org/singularity/quickmerge%3A0.3--pl5321h503566f_6>

* 安装方式（本地）：`mamba create -n quickmerge -c conda-forge -c bioconda quickmerge=0.3`

## 版本

* quickmerge **0.3**（官方 GitHub tag v0.3；bioconda / quay 官方 pin 0.3）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/quickmerge:0.3--pl5321h503566f_6 / depot.galaxyproject.org；本地不自建容器）

* 依赖：MUMmer（nucmer / delta-filter）——官方 conda 包自动包含；详见 `modules/mummer`

* 2026-09 核实：nf-core `modules/nf-core/quickmerge` 404、snakemake-wrappers `bio/quickmerge` 404、homebrew-core 无公式（brewsci/bio 有 quickmerge 公式 v0.3）
