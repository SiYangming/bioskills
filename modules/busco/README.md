# busco 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# busco / native — 自包含基因组完整性评估驱动

BUSCO 的本地自包含实现（`source_type: custom`、`type: native`；驱动 BUSCO 4.1.2）。

## 功能

BUSCO（Benchmarking Universal Single-Copy Orthologs）是一个用于评估基因组组装和基因预测完整性的工具。

四个子命令对应 BUSCO 评估链路：

| 子命令             | 命令                                                                        | 作用                                   |
| --------------- | ------------------------------------------------------------------------- | ------------------------------------ |
| `run`           | `busco -i <input> -m genome\|transcriptome\|proteins [-l <lineage>] -c N [--offline]` | 基于 OrthoDB 单拷贝直系同源基因评估完整性            |
| `list_datasets` | `busco --list-datasets`                                                   | 列出官方可用谱系数据集                          |
| `config`        | `busco_configurator.py <config.ini> <out.ini>`                            | 生成/定制配置（数据库路径、依赖工具路径等）              |
| `plot`          | `generate_plot.py -wd <dir> [-rt specific\|generic]`                      | 汇总多样本结果为图示（busco_figure.pdf/png）     |

## 用法

```bash
# CLI 直跑
python main.py run -i genome.fasta -m genome -l basidiomycota_odb10 -o busco_out --offline --threads 8
python main.py list_datasets
python main.py config config/config.ini my_config.ini
python main.py plot -wd busco_out -rt specific

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`run` 的 `--threads` 透传给 `busco -c`）。

## 实战示例：多样本基因集完整性对比

BUSCO 常用 `-m proteins` 对多个基因预测工具（AUGUSTUS / GeneMark / SNAP / MAKER / BRAKER / EVM / GETA 等）的输出做统一评估，比较完整度。以下为教学流程的典型批量用法，等价能力由 `native/main.py` 的 `run` / `plot` 子命令提供（见上「用法」）。

### 1. 逐个基因集运行 BUSCO（蛋白模式，离线）

```bash
mkdir -p busco_out
for i in protein_files/proteins.*.fasta; do
    x=$(basename "$i" .fasta); x=${x/proteins./}
    busco -i "$i" -c 8 -o "$x" -m proteins -l /path/to/databases/basidiomycota_odb10 --offline
done
```

### 2. 汇总结果并可视化

```bash
grep C: */*/short_summary*.txt > BUSCO.summary.txt
cd busco_out
ln -sf */short_summary* .
generate_plot.py -wd ./ -rt specific
```

### 3. 参数说明

| 参数               | 说明                          |
| ---------------- | --------------------------- |
| `-i input.fasta` | 输入序列（基因组 / 转录组 / 蛋白）        |
| `-c 8`           | 并行线程数                       |
| `-o out_name`    | 输出目录名                       |
| `-m proteins`    | 分析模式：`genome` / `transcriptome` / `proteins` |
| `-l <lineage>`   | 谱系数据库名或本地路径                 |
| `--offline`      | 离线模式（仅用本地数据库）               |
| `--auto-lineage` | 自动选择最优谱系数据集（需联网下载）          |

### BUSCO 评估指标

| 指标 | 说明           |
| --- | ------------ |
| C  | 完整的 BUSCO 基因 |
| S  | 单拷贝的完整基因     |
| D  | 多拷贝的完整基因     |
| F  | 片段化基因        |
| M  | 缺失基因         |

## 谱系数据库（lineage datasets）

BUSCO 本体不捆绑数据库，**必须单独下载** OrthoDB 谱系数据集后使用（`--offline` 时代码只读本地数据库）：

```bash
# 1) 查看官方可用数据集（联网）
busco --list-datasets > Lineage_datasets.txt

# 2) 下载 v4 谱系数据集（示意：真菌相关）
mkdir -p databases && cd databases
wget https://busco-data.ezlab.org/v4/data/lineages/fungi_odb10.2019-12-13.tar.gz
wget https://busco-data.ezlab.org/v4/data/lineages/basidiomycota_odb10.2019-11-20.tar.gz
wget https://busco-data.ezlab.org/v4/data/lineages/ascomycota_odb10.2019-11-20.tar.gz
tar zxf fungi_odb10.2019-12-13.tar.gz
tar zxf basidiomycota_odb10.2019-11-20.tar.gz
tar zxf ascomycota_odb10.2019-11-20.tar.gz

# 3) 指定本地数据库运行（-l 用绝对路径 or 由 config 的 download_path 指向 databases 目录）
busco -i genome.fasta -m genome -l /path/to/databases/basidiomycota_odb10 -c 8 --offline
```

> 说明：v4 数据库接口与 BUSCO 4.x 匹配；若使用 conda/镜像的 6.x（见「版本」），请改用对应的 v5/odb12 数据源与 `--download_path`/`--offline` 语义。数据库未就位时 `run` 会明确报错。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具本体；`main.py` 驱动在宿主机跑（conda/mamba 装 busco）。

### 1. Conda / brew（包管理器安装）

```bash
# 按教学文档登记版本 4.1.2（亦可省略 =4.1.2 取当前最新 6.1.0）
mamba create -n busco-native -c conda-forge -c bioconda busco=4.1.2
conda activate busco-native
busco --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install busco
busco --version          # 断言
# 注：brewsci/bio busco 公式当前 5.0.0（gitlab archive 5.0.0），与 meta 登记 4.1.2 略有差异（版本以 formula 为准）
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境；无 conda 时走官方源码 `python3 setup.py install`，部署到 `~/software/busco-4.1.2`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/busco:4.1.2--py38h3252c3a_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/busco:4.1.2--py38h3252c3a_2 \
    busco -i /data/genome.fasta -m genome -l basidiomycota_odb10 -o /data/busco_out -c 8 --offline
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull busco.sif docker://depot.galaxyproject.org/singularity/busco:4.1.2--py38h3252c3a_2
apptainer run -B $PWD:/data -H /data busco.sif \
    busco -i /data/genome.fasta -m genome -l basidiomycota_odb10 -o /data/busco_out -c 8 --offline
```

### 4. 官方源码（并列保留）

官方同时提供源码归档（GitLab tag `4.1.2`），可作为无容器/无 conda 场景的并列路线（`python3 setup.py install`）：

```bash
wget https://gitlab.com/ezlab/busco/-/archive/4.1.2/busco-4.1.2.tar.gz -P ~/software
tar zxf ~/software/busco-4.1.2.tar.gz -C ~/software/
cd ~/software/busco-4.1.2/
python3 setup.py install            # 或 pip3 install .
./scripts/busco_configurator.py config/config.ini config/myconfig.ini
export BUSCO_CONFIG_FILE=~/software/busco-4.1.2/config/config.ini
export PATH="$PATH:$HOME/software/busco-4.1.2/bin/"
busco --version

pip3 install intervaltree==3.0.0 bio -i https://mirrors.aliyun.com/pypi/simple/
```

> 依赖：`-m genome`（真核）需要 metaeuk / SEPP，原核需要 Prodigal；比对依赖 diamond / blast。conda 安装会自动带入这些依赖；源码安装需自行准备。官方源码归档为 GitLab 动态打包 tarball（摘要不稳定），`install.sh --method source` 会跳过内嵌 sha256 校验。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch 解析，覆盖 4 个子命令）；busco 已安装时额外冒烟 --version
```

## 版本

* busco 4.1.2（bioconda `busco=4.1.2` / GitLab tag `4.1.2`）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/busco / depot.galaxyproject.org；本地不再自建容器）
* nf-core 五个子模块（busco/download/generateplot/phylogenomics/plot）与官方 snakemake-wrappers（`v9.17.1/bio/busco`）当前均 pin **busco=6.1.0**，与 native 登记的 4.1.2 相差较大，跨引擎迁移需注意

## 容器与 Conda 链接

* **官网**：https://busco.ezlab.org/
* **GitLab**：https://gitlab.com/ezlab/busco
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/busco/overview>
* **Docker**：`docker pull quay.io/biocontainers/busco:4.1.2--py38h3252c3a_2`
* **Singularity**：<https://depot.galaxyproject.org/singularity/busco%3A4.1.2--py38h3252c3a_2>
* **谱系数据库**：<https://busco-data.ezlab.org/v4/data/lineages/>
* 安装方式（本地）：`mamba create -n busco -c conda-forge -c bioconda busco=4.1.2`
