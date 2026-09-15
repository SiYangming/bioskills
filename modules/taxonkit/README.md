# taxonkit 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 已存在（见文末「版本」），依仓库规范**不单独建目录**，仅登记于此。

---

## native 实现

# taxonkit / native — 自包含 NCBI Taxonomy 处理驱动

TaxonKit 的本地自包含实现（`source_type: custom`、`type: native`，版本 0.2.4）。

## 功能

TaxonKit 是一个用于处理 NCBI 分类数据库的命令行工具，支持物种分类树查询、序列子集提取等功能，常用于从 NR 数据库中按分类单元提取子集。

| 子命令         | 命令                                                                 | 作用                             |
| ----------- | ------------------------------------------------------------------ | ------------------------------ |
| `list`      | `taxonkit list --ids <taxid> -j N [--indent ""] [-o out]`          | 列出指定 TaxID 下所有子单元（如真菌界 4751）    |
| `lineage`   | `taxonkit lineage [--data-dir DIR] <taxids.txt> [-n] [-r] [-o out]` | 查询 TaxID 谱系（可附分类名称/等级）         |
| `name2taxid` | `taxonkit name2taxid [--data-dir DIR] <names.txt> -j N [-o out]`   | 物种名 → TaxID 映射                 |
| `reformat`  | `taxonkit reformat [--data-dir DIR] -i <lineage.tsv> -f <fmt>`      | 把 lineage 结果格式化为多级分类（界门纲目科属种）   |
| `version`   | `taxonkit version`                                                  | 打印版本                          |

> NCBI Taxonomy 数据目录通过 `--data-dir` 指定（默认 `~/.taxonkit`，需含 `nodes.dmp`/`names.dmp` 等，
> 由 `taxdump.tar.gz` 解压得到，见下方「实战示例 §1」）。

## 用法

```bash
# CLI 直跑
python main.py list --ids 4751 -j 8 -o sub.fungi.list
python main.py lineage --data-dir ~/.taxonkit taxids.txt -n -r -o lineage.tsv
python main.py name2taxid --data-dir ~/.taxonkit names.txt -j 8 -o name2taxid.tsv
python main.py reformat --data-dir ~/.taxonkit -i lineage.tsv -f "{k};{p};{c};{o};{f};{g};{s}" -o taxonomy.tsv
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`-j` 仅对 `list` / `name2taxid` 注入）。

## 实战示例：从 NR 数据库提取真菌子集

TaxonKit 常用于按分类单元裁剪大型序列库（NCBI NR），显著降低同源搜索规模。以下步骤的等价能力由
`native/main.py` 的 `list` / `lineage` / `name2taxid` / `reformat` 子命令提供（见上「用法」）。

### 1. 准备分类数据库

```bash
mkdir -p ~/.taxonkit
tar zxf taxdump.tar.gz -C ~/.taxonkit        # 解压 NCBI taxonomy 转储
ls ~/.taxonkit/{nodes.dmp,names.dmp}         # 断言关键文件
```

### 2. 提取真菌界（TaxID 4751）所有子单元列表

```bash
# 等价：python main.py list --ids 4751 -j 8 -o sub.fungi.list
taxonkit list -j 8 --ids 4751 > sub.fungi.list
```

### 3. 依据列表从 NR 中抽取真菌序列并建库

```bash
gzip -dc nr.gz \
  | perl extract_sub_data_from_Nr.pl --sub_taxon sub.fungi.list --acc2taxid prot.accession2taxid - \
  > nr_fungi.fasta
makeblastdb -in nr_fungi.fasta -dbtype prot -title nr_fungi -parse_seqids -out nr_fungi -logfile nr_fungi.log
diamond makedb --db nr_fungi --in nr_fungi.fasta
```

### 4. 常用分类单元编号

| 分类单元 | TaxID  |
| ----- | ------ |
| 古菌    | 2157   |
| 细菌    | 2      |
| 病毒    | 10239  |
| 真菌    | 4751   |
| 植物    | 3193   |
| 动物    | 33208  |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
本工具官方**同时提供预编译二进制包与源码编译两条路线**，均保留（预编译为首选）。main.py 驱动在宿主机跑。

### 1. 官方预编译二进制包（首选）

* **下载页**：<https://github.com/shenwei356/taxonkit/releases/tag/v0.2.4>

```bash
# 下载（linux-x64；macOS 用 taxonkit_darwin_amd64.tar.gz）
wget https://github.com/shenwei356/taxonkit/releases/download/v0.2.4/taxonkit_linux_amd64.tar.gz -P ~/software/

# 解压到用户目录并加 PATH（无需 root，禁 /opt/biosoft 类硬编码）
mkdir -p ~/software/taxonkit-0.2.4
tar zxf ~/software/taxonkit_linux_amd64.tar.gz -C ~/software/taxonkit-0.2.4 --strip-components=1
echo 'export PATH=$PATH:~/software/taxonkit-0.2.4' >> ~/.bashrc
source ~/.bashrc
taxonkit version
```

> 一键安装可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `taxonkit`，
> 无 conda 时自动下载官方 release 二进制到 `~/software/taxonkit-<ver>` 并写 PATH；版本默认 0.2.4，
> 内嵌 linux-x64 / macos-x64 两份 sha256；用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留，需 Go 工具链）

官方为 Go 实现，源码见 <https://github.com/shenwei356/taxonkit>：

```bash
# 需先安装 Go（https://go.dev/doc/install）
git clone --depth 1 --branch v0.2.4 https://github.com/shenwei356/taxonkit.git
cd taxonkit
go build -o ~/software/taxonkit-0.2.4/taxonkit .   # 产物与预编译包同一二进制
~/software/taxonkit-0.2.4/taxonkit version
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n taxonkit-native -c conda-forge -c bioconda taxonkit=0.2.4
conda activate taxonkit-native
taxonkit version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install taxonkit
taxonkit version   # 断言（brew 当前 0.20.0，与 meta 登记 0.2.4 略有差异，版本以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/taxonkit:0.2.4--0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/taxonkit:0.2.4--0 \
    list --ids 4751 -j 8 -o sub.fungi.list
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull taxonkit.sif docker://depot.galaxyproject.org/singularity/taxonkit:0.2.4--0
apptainer run -B $PWD:/data -H /data taxonkit.sif list --ids 4751 -j 8 -o /data/sub.fungi.list
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（真实运行需 ~/.taxonkit 分类数据库）
```

## 版本

* taxonkit 0.2.4（bioconda::taxonkit=0.2.4；与 13.md 教程及官方 release v0.2.4 对齐）

* 构建路线：官方镜像/conda/预编译二进制提供（quay.io/biocontainers/taxonkit:0.2.4--0 / depot.galaxyproject.org；本地不再自建容器）

* 官方登记（不建目录）：nf-core `taxonkit/{lineage,list,name2taxid}`（env pin 分别为 0.18.0 / 0.20.0 / 0.15.1）；
  snakemake-wrappers `bio/taxonkit` 扁平 wrapper（tag v9.17.1，taxonkit=0.20.0）——均高于本 native 的 0.2.4，跨引擎迁移时注意版本差异

* 绑定说明：nf-core 执行请用 `nf-core modules install taxonkit <sub>` 安装到项目自身目录；snakemake 运行时靠
  `wrapper: "v9.17.1/bio/taxonkit"` 句柄解析，不要直接引用本仓库示例

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/taxonkit/overview>

* **Docker**：`docker pull quay.io/biocontainers/taxonkit:0.2.4--0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/taxonkit%3A0.2.4--0>

* 安装方式（本地）：`mamba create -n taxonkit -c conda-forge -c bioconda taxonkit=0.2.4`
