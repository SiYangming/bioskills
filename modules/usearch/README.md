# usearch 软件模块

> 汇总说明：本 README 说明 USEARCH（usearch）native 实现的用法；安装方式见下方各节，容器与 conda 信息记录于此。

***

## ⚠️ 许可声明（务必阅读）

* **USEARCH 是 drive5 的商业软件**：学术使用免费，但需在官网 <https://www.drive5.com/usearch/>
  **注册后下载**，并遵守 **USEARCH License**（<https://www.drive5.com/usearch/license.html>）。
  **商业使用前请自行确认已获得授权。**
* 本模块登记的 **8.1.1861 属「历史版本二进制」**：由作者在
  <https://github.com/rcedgar/usearch_old_binaries/> 以 **CC0-1.0（public domain）** 重发布
  （bioconda 亦据此打包，标注 `license=CC0`）。
* 更新版本：`usearch12`（<https://github.com/rcedgar/usearch12>）为开源，GitHub 识别为 GPL-3.0；
  但其命令行接口与 8.1.1861 有差异。
* 因此本模块 `native/install.sh` 的 **binary 路线不内置任何需注册的下载链接**，仅提示用户自行获取授权副本；
  容器与 conda 路线来自官方渠道（bioconda/quay），可免注册获取 8.1.1861。

***

## native 实现

# usearch / native — 自包含序列分析驱动（USEARCH 8.1.1861）

USEARCH 的本地自包含实现（`source_type: custom`、`type: native`）。USEARCH 以「子命令旗标」形式调用，
本驱动把 6 个核心旗标封装为子命令：

| 子命令                | 命令（核心参数）                                                                       | 作用                         |
| ------------------ | ------------------------------------------------------------------------------ | -------------------------- |
| `cluster_otus`     | `usearch -cluster_otus <in> -otus <out> [-relabel X -minsize N]`                 | UPARSE 去噪聚类，输出 OTU 代表序列    |
| `uchime_denovo`    | `usearch -uchime_denovo <in> -uchimeout <out> [-chimeras f]`                     | de novo 嵌合体检测（需 ;size=N）   |
| `uchime_ref`       | `usearch -uchime_ref <in> -db <ref> -uchimeout <out> [-strand plus]`             | 参考库模式嵌合体检测                 |
| `usearch_global`   | `usearch -usearch_global <in> -db <ref> [-id X -otutabout f]`                    | 比对到参考库并生成 OTU table         |
| `derep_fulllength` | `usearch -derep_fulllength <in> -output <out> [-sizeout -relabel X]`             | 全长度去冗余（得到 unique 序列）        |
| `cluster_fast`     | `usearch -cluster_fast <in> [-id X -centroids f]`                                | 按相似度快速聚类                   |

> 说明：搜索类子命令（`usearch_global` / `uchime_ref` / `cluster_fast`）支持 `-threads`（自动注入）；
> `cluster_otus` / `uchime_denovo` / `derep_fulllength` 为单线程，不注入线程参数。

## 用法

```bash
# CLI 直跑
python main.py derep_fulllength seqs.fa -o uniques.fa --sizein --sizeout
python main.py cluster_otus uniques.fa -o otus.fa --relabel OTU --minsize 2
python main.py uchime_denovo seqs.fa -o chimeras.uchime --chimeras chim.fa
python main.py usearch_global seqs.fa -d ref.fa --id 0.97 --strand plus --otutabout otu_table.txt --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：UPARSE 去噪 → OTU 表（16S）

USEARCH 速度极快，其 UPARSE / UCHIME 算法是 16S 微生物组 OTU 挑选与嵌合体去除的经典方案；
等价能力由 `native/main.py` 的 `derep_fulllength` / `cluster_otus` / `uchime_ref` / `usearch_global` 子命令提供。

```bash
# 1) 去冗余（得到 unique 序列，含丰度 ;size=N）
python main.py derep_fulllength seqs.fa -o uniques.fa --sizein --sizeout

# 2) UPARSE 去噪聚类，得到 OTU 代表序列（-minsize 2 丢弃 singletons）
python main.py cluster_otus uniques.fa -o otus.fa --relabel OTU --minsize 2

# 3) 参考库模式嵌合体检测（UCHIME）
python main.py uchime_ref otus.fa -d gold.fa -o chimeras.uchime --nonchimeras otus_nonchim.fa --strand plus --threads 8

# 4) 把全部 reads 比对到 OTU 代表序列，生成 OTU table
python main.py usearch_global seqs.fa -d otus.fa --id 0.97 --strand plus \
    --otutabout otu_table.txt --threads 8
```

### 参数说明

| 参数                     | 适用                              | 说明                    |
| ---------------------- | ------------------------------- | --------------------- |
| `-o` (`-otus`/`-uchimeout`/`-output`) | cluster_otus/uchime_*/derep | 主输出（驱动统一暴露 `-o/--output`） |
| `-db`                  | uchime_ref/usearch_global       | 参考库 FASTA             |
| `-id`                  | usearch_global/cluster_fast     | 最小一致性阈值（如 0.97）       |
| `-strand`              | uchime_ref/usearch_global       | plus / both           |
| `-otutabout`           | usearch_global                  | OTU table（tab 分隔）      |
| `-centroids`           | cluster_fast                    | 聚类中心序列输出              |
| `-sizein` / `-sizeout` | 多子命令                            | 读/写丰度标签 ;size=N       |
| `-threads`             | 搜索类子命令                          | 线程数（自动注入）             |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。

> ⚠️ **许可限制**：USEARCH 为 drive5 商业软件（学术免费、需注册、须遵守 USEARCH License）。
> 本模块 8.1.1861 历史二进制经 `rcedgar/usearch_old_binaries` 以 CC0-1.0 重发布；商业使用前请阅读许可。

### 1. Conda（包管理器安装）

```bash
mamba create -n usearch-native -c conda-forge -c bioconda usearch=8.1.1861
conda activate usearch-native
usearch    # 断言（打印含版本号的 banner）
```

> Homebrew：homebrew-core 与 brewsci/bio 两源均**无 usearch 公式**（2026-09 核实 404），故不登记 brew 块。
>
> 一键安装可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `usearch`；
> **binary 路线因许可限制不自动下载**，仅校验你自行获取的二进制——见下）。
> 用法：`bash native/install.sh --help`。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/usearch:8.1.1861--h9ee0642_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/usearch:8.1.1861--h9ee0642_0 \
    usearch -cluster_otus /data/uniques.fa -otus /data/otus.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull usearch.sif docker://depot.galaxyproject.org/singularity/usearch:8.1.1861--h9ee0642_0
apptainer run -B $PWD:/data -H /data usearch.sif \
    usearch -cluster_otus /data/uniques.fa -otus /data/otus.fa
```

### 4. 用户自备二进制（许可受限，需自行获取）

USEARCH 官方**仅通过 drive5 官网注册后**提供下载（**本仓库不内置任何需注册的下载链接**）。若你已获授权副本：

```bash
# 将自行下载的 usearch 放到 PATH（或指定路径校验）
bash native/install.sh --method binary --bin /path/to/usearch
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证为主；usearch 已安装时追加真实去冗余冒烟
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/usearch/overview>

* **Docker**：`docker pull quay.io/biocontainers/usearch:8.1.1861--h9ee0642_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/usearch%3A8.1.1861--h9ee0642_0>

* **官网 / 许可**：<https://www.drive5.com/usearch/> ｜ <https://www.drive5.com/usearch/license.html>

* 安装方式（本地）：`mamba create -n usearch -c conda-forge -c bioconda usearch=8.1.1861`

## 版本

* usearch 8.1.1861（bioconda::usearch=8.1.1861；官方容器 `usearch:8.1.1861--h9ee0642_0`）

* 许可：⚠️ 上游 USEARCH 为商业软件（学术免费、需注册、须遵守 USEARCH License）；
  8.x 历史二进制经 `rcedgar/usearch_old_binaries` 以 CC0-1.0 重发布（bioconda 标注 CC0）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/usearch / depot.galaxyproject.org；本地不维护容器配方）

* nf-core / snakemake-wrappers：均无（2026-09 抓取 404）
