# interproscan 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core 子模块已存在（见文末「版本」），依仓库规范**不单独建目录**，仅登记于此；官方 snakemake-wrappers 无 interproscan。

---

## native 实现

# interproscan / native — 自包含蛋白质功能域注释驱动

InterProScan 的本地自包含实现（`source_type: custom`、`type: native`，版本 5.59_91.0，
命令 `interproscan.sh`，依赖 Java）。

## 功能

InterProScan 是 EMBL-EBI 开发的蛋白质功能域注释工具，整合了 Pfam、SMART、PROSITE、TIGRFAMs 等多个数据库的特征识别方法，可一次性获得蛋白质家族、结构域、功能位点等注释信息，同时可提取 GO 注释。

| 子命令       | 命令                                                                                                                            | 作用                        |
| --------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `run`     | `interproscan.sh -i <fasta> -o <out> -f tsv,gff3,xml -goterms -iprlookup -pa -cpu N --tempdir DIR`                             | 蛋白功能域注释（多数据库整合，含 GO/IPR）   |
| `version` | `interproscan.sh --version`                                                                                                    | 打印版本                      |

> 依赖 Java：`env_vars` 已透传 `JAVA_OPTS`（`-Xmx{mem_mb}m -Djava.io.tmpdir={tmpdir}`），
> 大蛋白集建议调大 `default_mem_mb`。

## 用法

```bash
# CLI 直跑（InterProScan 使用示例）
python main.py run -i proteins.fasta -o interpro_result -f tsv,gff3,xml \
    -goterms -iprlookup -pa -cpu 8
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（映射为 `-cpu` / `--tempdir`）。

## 实战示例：批量注释 + 提取 InterPro / GO

InterProScan 一次性整合 Pfam、SMART、PROSITE、TIGRFAMs、SuperFamily 等多个数据库，输出蛋白家族、
结构域、功能位点注释，并可提取 InterPro（IPR）与 GO 注释。等价能力由 `native/main.py` 的 `run`
子命令提供（见上「用法」）。

### 1. 运行注释（多格式输出）

```bash
# 等价：python main.py run -i proteins.fasta -o interpro_result -f tsv,gff3,xml -goterms -iprlookup -pa -cpu 8
interproscan.sh -i proteins.fasta -o interpro_result -f tsv,gff3,xml -goterms -iprlookup -pa -cpu 8
```

### 2. 合并结果并提取注释

```bash
# 批量结果合并（多文件场景）
cat interpro5/*gff* > interpro.gff
cat interpro5/*tsv* > interpro.tsv

# 提取 InterPro 注释（IPR 行，取序列 ID + IPR 号 + 描述列）
grep IPR interpro.tsv | cut -f 1,12,13 | gene_annotation_from_table.pl - > Interpro.txt

# 提取 GO 注释
grep "GO:" interpro.tsv | cut -f 1,14 | tr ';' '\n' | sort -u > interpro_go.txt
```

### 3. 主要输出格式

| 格式   | 说明                    |
| ---- | --------------------- |
| TSV  | 制表符分隔，便于解析            |
| GFF3 | 通用特征格式，可用于基因组浏览器      |
| XML  | 完整 XML 结果             |

## 环境安装（官方源码安装优先；Conda / 官方镜像并列）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
本工具官方**仅提供源码归档（无预编译二进制资产，已核实）**，源码安装与 conda 并列为推荐路线。main.py 驱动在宿主机跑。
**依赖 Java**，官方发行包自带 JRE；分析数据在发行包 `data/` 下。

### 1. 官方源码安装（首选）

* **下载页**：<https://www.ebi.ac.uk/interpro/download/>
* **GitHub**：<https://github.com/ebi-pf-team/interproscan>

```bash
# 下载 5.59-91.0 源码归档（官方 tag 用连字符）
wget https://github.com/ebi-pf-team/interproscan/archive/5.59-91.0.tar.gz -O ~/software/interproscan-5.59_91.0.tar.gz

# 解压到用户目录（无需 root，禁 /opt/biosoft 类硬编码）
mkdir -p ~/software/interproscan-5.59_91.0
tar zxf ~/software/interproscan-5.59_91.0.tar.gz -C ~/software/interproscan-5.59_91.0 --strip-components=1
echo 'export PATH=$PATH:~/software/interproscan-5.59_91.0' >> ~/.bashrc
source ~/.bashrc
interproscan.sh --version   # 断言

# 下载分析数据（体积大，按需执行）
cd ~/software/interproscan-5.59_91.0 && python3 setup.py -f interproscan.properties
```

> 一键安装可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `interproscan`，
> 无 conda 时下载官方源码归档到 `~/software/interproscan-<ver>` 并写 PATH；版本默认 5.59_91.0；
> 用法：`bash native/install.sh --help`）。

### 2. Conda（包管理器安装，备选）

```bash
mamba create -n interproscan-native -c conda-forge -c bioconda interproscan=5.59_91.0
conda activate interproscan-native
interproscan.sh --version   # 断言
```

> brew：homebrew-core 与 brewsci/bio 均无 interproscan 公式（2026-09 核实 404），故不提供 brew 安装块。

### 3. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/interproscan:5.59_91.0--hec16e2b_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/interproscan:5.59_91.0--hec16e2b_1 \
    interproscan.sh -i proteins.fasta -o interpro_result -f tsv,gff3,xml -goterms -iprlookup -cpu 8
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull interproscan.sif docker://depot.galaxyproject.org/singularity/interproscan:5.59_91.0--hec16e2b_1
apptainer run -B $PWD:/data -H /data interproscan.sif \
    interproscan.sh -i /data/proteins.fasta -o /data/interpro_result -f tsv,gff3,xml -goterms -iprlookup -cpu 8
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证 + JAVA_OPTS 透传断言（真实注释需分析数据）
```

## 版本

* interproscan 5.59_91.0（bioconda::interproscan=5.59_91.0；bioconda 当前最新版）

* 构建路线：官方镜像/conda/源码归档提供（quay.io/biocontainers/interproscan:5.59_91.0--hec16e2b_1 / depot.galaxyproject.org；本地不再自建容器）

* 官方登记（不建目录）：nf-core 扁平子模块 `interproscan`（env pin bioconda::interproscan=5.59_91.0，
  容器 quay.io/biocontainers/interproscan:5.59_91.0--hec16e2b_1，与 native 版本一致）；
  snakemake-wrappers `bio/interproscan` **404**（无官方 wrapper）

* 绑定说明：nf-core 执行请用 `nf-core modules install interproscan` 安装到项目自身目录，不要直接引用本仓库示例

## 容器与 Conda 链接

* **InterProScan 官网**：https://www.ebi.ac.uk/interpro/search/sequence/

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/interproscan/overview>

* **Docker**：`docker pull quay.io/biocontainers/interproscan:5.59_91.0--hec16e2b_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/interproscan%3A5.59_91.0--hec16e2b_1>

* 安装方式（本地）：`mamba create -n interproscan -c conda-forge -c bioconda interproscan=5.59_91.0`
