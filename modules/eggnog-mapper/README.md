# eggnog-mapper 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers **均无** eggnog-mapper（2026-09 抓取 404），无官方登记层。

---

## native 实现

# eggnog-mapper / native — 自包含 eggNOG 功能注释驱动

eggNOG-mapper 的本地自包含实现（`source_type: custom`、`type: native`，版本 1.0.3，
数据库 emapperdb-4.5.1）。命令为 `emapper.py`。

## 功能

eggNOG-mapper 是基于 eggNOG 数据库的快速功能注释工具，通过同源映射将基因序列注释到 eggNOG 同源组，可获得 GO、KEGG、COG 等多种功能注释信息。

| 子命令             | 命令                                                                                          | 作用                     |
| --------------- | ------------------------------------------------------------------------------------------- | ---------------------- |
| `annotate`      | `emapper.py -i <fasta> -o <out> -m diamond --cpu N --data_dir <db>`                          | 蛋白 FASTA 功能注释（同源搜索 + 注释） |
| `annotate_hits` | `emapper.py --annotate_hits_table <hits> -o <out> --cpu N --data_dir <db>`                   | 基于预计算命中表注释              |
| `download_db`   | `download_eggnog_data.py -y -f --data_dir <dir>`                                             | 下载 eggNOG 数据库（emapperdb） |

## 用法

```bash
# CLI 直跑（数据库目录指向 emapperdb-4.5.1 解压处）
python main.py annotate -i proteins.fasta -o eggNOG -m diamond \
    --data_dir ~/db/emapperdb-4.5.1 --tax_scope Fungi --target_orthologs one2one --threads 8
python main.py annotate_hits --annotate_hits_table hits.tsv -o eggNOG --data_dir ~/db/emapperdb-4.5.1
python main.py download_db --data_dir ~/db

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--cpu` 自动注入）。

## 实战示例：本地批量 eggNOG 注释

eggNOG-mapper 通过同源映射，把基因序列注释到 eggNOG 同源组，可获得 GO / KEGG / COG 等多类注释；
在线工具（<http://eggnog-mapper.embl.de/>）适合少量序列（教程记录耗时约 2h19min），大批量请本地运行。
等价能力由 `native/main.py` 的 `annotate` / `annotate_hits` 子命令提供（见上「用法」）。

### 1. 下载并部署数据库（emapperdb-4.5.1）

```bash
# 推荐用官方下载脚本（自动获取并解压到 --data_dir）
download_eggnog_data.py -y -f --data_dir ~/db
# 等价：python main.py download_db --data_dir ~/db
```

> 教程给出的直链为 `http://eggnogdb.embl.de/download/emapperdb-4.5.1/{og2level.tsv.gz,eggnog.db.gz,OG_fasta.tar.gz,eggnog_proteins.dmnd.gz}`，
> 解压到 emapperdb 目录。2026-09 核实 `eggnogdb.embl.de` 域名已无法解析，请以上游 GitHub / 官方下载脚本获取。

### 2. 本地运行注释

```bash
# -m diamond：DIAMOND 搜索（推荐，快）；--cpu 线程
emapper.py -i proteins.fasta -o eggNOG -m diamond --cpu 8 --data_dir ~/db/emapperdb-4.5.1
```

### 3. 处理结果

```bash
mkdir -p /path/13.functional_annotation/eggNOG && cd $_
cp query_seqs.fa.emapper.* ./
ln -s query_seqs.fa.emapper.annotations eggNOG.annot   # 注释主表
```

## 环境安装（官方源码安装优先；Conda / 官方镜像并列）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
本工具官方**仅提供源码归档（无预编译二进制资产，已核实）**，源码安装与 conda 并列为推荐路线。main.py 驱动在宿主机跑。
数据库 emapperdb 需单独下载（体积大，不入镜像）。

### 1. 官方源码安装（首选）

* **GitHub**：<https://github.com/eggnogdb/eggnog-mapper>
* **数据库下载**：<http://eggnogdb.embl.de/#/app/downloads>（或 `download_eggnog_data.py`）

```bash
# 下载 1.0.3 源码归档
wget https://github.com/eggnogdb/eggnog-mapper/archive/refs/tags/1.0.3.tar.gz -O ~/software/eggnog-mapper-1.0.3.tar.gz

# 解压到用户目录（无需 root，禁 /opt/biosoft 类硬编码）
mkdir -p ~/software/eggnog-mapper-1.0.3
tar zxf ~/software/eggnog-mapper-1.0.3.tar.gz -C ~/software/eggnog-mapper-1.0.3 --strip-components=1
echo 'export PATH=$PATH:~/software/eggnog-mapper-1.0.3' >> ~/.bashrc
source ~/.bashrc
emapper.py --help

# 数据库（需单独下载，教程使用 emapperdb-4.5.1）
download_eggnog_data.py -y -f --data_dir ~/db
```

> 一键安装可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `eggnog-mapper`，
> 无 conda 时下载官方源码归档到 `~/software/eggnog-mapper-<ver>` 并写 PATH；版本默认 1.0.3；
> 用法：`bash native/install.sh --help`）。

### 2. Conda（包管理器安装，备选）

```bash
mamba create -n eggnog-mapper-native -c conda-forge -c bioconda eggnog-mapper=1.0.3
conda activate eggnog-mapper-native
emapper.py --help   # 断言
```

> brew：homebrew-core 与 brewsci/bio 均无 eggnog-mapper 公式（2026-09 核实 404），故不提供 brew 安装块。
> 注意：1.0.3 为 Python 2.7 实现（bioconda 构建为 py27/py_3）；如无历史约束，可考虑 2.1.x（Python 3）。

### 3. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/eggnog-mapper:1.0.3--py_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/eggnog-mapper:1.0.3--py_3 \
    emapper.py -i proteins.fasta -o eggNOG -m diamond --cpu 8 --data_dir /data/emapperdb-4.5.1
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull eggnog-mapper.sif docker://depot.galaxyproject.org/singularity/eggnog-mapper:1.0.3--py_3
apptainer run -B $PWD:/data -H /data eggnog-mapper.sif \
    emapper.py -i /data/proteins.fasta -o eggNOG -m diamond --cpu 8 --data_dir /data/emapperdb-4.5.1
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（真实注释需 emapperdb 数据库）
```

## 版本

* eggnog-mapper 1.0.3（bioconda::eggnog-mapper=1.0.3）；配套数据库 emapperdb-4.5.1

* 构建路线：官方镜像/conda/源码归档提供（quay.io/biocontainers/eggnog-mapper:1.0.3--py_3 / depot.galaxyproject.org；本地不再自建容器）

* 官方登记：nf-core `eggnog-mapper` **404**、snakemake-wrappers `bio/eggnog-mapper` **404**（2026-09 抓取）——均无官方实现，Snakemake/Nextflow 场景请走本模块 native

* brew：homebrew-core / brewsci-bio 均无公式（404）

## 容器与 Conda 链接

* **eggNOG-mapper 官网**：<https://eggnog-mapper.cgmlab.org/>

* **GitHub**：<https://github.com/eggnogdb/eggnog-mapper>

* **数据库下载**：<https://eggnogdb.org/>

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/eggnog-mapper/overview>

* **Docker**：`docker pull quay.io/biocontainers/eggnog-mapper:1.0.3--py_3`

* **Singularity**：<https://depot.galaxyproject.org/singularity/eggnog-mapper%3A1.0.3--py_3>

* 安装方式（本地）：`mamba create -n eggnog-mapper -c conda-forge -c bioconda eggnog-mapper=1.0.3`
