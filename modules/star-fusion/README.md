# star-fusion 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09 逐渠道核实）。
> STAR-Fusion 是基于 STAR 比对器的融合基因检测工具（推荐），速度快、准确性高；运行前必须准备 CTAT 资源库（`--genome_lib_dir`）。

***

## native 实现

# star-fusion / native — STAR-Fusion 融合检测驱动（推荐）

STAR-Fusion 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对齐教学文档
「3.14.3 STAR-Fusion（推荐）」与「12.3 STAR-Fusion（推荐）」。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `detect` | `STAR-Fusion --genome_lib_dir <CTAT_resource_lib> --left_fq R1 [--right_fq R2] --output_dir <dir> --CPU N` | 融合基因检测（单/双端 RNA-seq） |

参数说明：

| 参数 | 说明 |
| --- | --- |
| `--genome_lib_dir` | CTAT 资源库目录（含 STAR 索引、注释与融合参考；必需） |
| `--left_fq` | 输入 reads mate1（单端时即唯一输入） |
| `--right_fq` | 输入 reads mate2（单端数据省略） |
| `--output_dir` | 输出目录 |
| `--CPU` | CPU 线程数（自动注入；默认 8） |

主要输出：

| 文件 | 说明 |
| --- | --- |
| `star-fusion.fusion_predictions.tsv` | 融合基因预测结果 |
| `star-fusion.fusion_predictions.abridged.tsv` | 简化版结果 |

> 重要列：`FusionName`（基因A--基因B）、`JunctionReadCount`（比对到融合位点的 reads 数）、
> `SpanningFragCount`（跨越融合位点的片段数）、`SpliceType`（剪接类型：已知/新的）。

## 用法

```bash
# CLI 直跑（文档 12.3 示例参数）
python main.py detect --genome_lib_dir /path/to/CTAT_resource_lib \
    --left_fq reads_1.fastq.gz --right_fq reads_2.fastq.gz --output_dir . --CPU 8
# 单端
python main.py detect --genome_lib_dir /path/to/CTAT_resource_lib \
    --left_fq reads.fastq.gz --output_dir . --CPU 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：RNA-seq 融合基因检测（含 CTAT 资源库准备）

以下为教学文档「12.3 STAR-Fusion」的典型用法（等价能力由 `native/main.py` 的 `detect` 子命令提供，
见上「用法」）。

```bash
# 0) 准备 CTAT 资源库（--genome_lib_dir 必需）
#    从 CTAT 下载预构建库，或用官方 prep_genome_lib.pl 本地构建：
#    https://github.com/NCIP/CTAT_genome_lib_build_DIR
#    （下载/构建后得到 CTAT_resource_lib 目录，含 STAR 索引与注释）

mkdir -p star_fusion && cd star_fusion

# 1) 运行 STAR-Fusion
STAR-Fusion \
    --genome_lib_dir /path/to/CTAT_resource_lib \
    --left_fq ../reads_1.fastq.gz \
    --right_fq ../reads_2.fastq.gz \
    --output_dir . \
    --CPU 8

# 2) 结果
#    star-fusion.fusion_predictions.tsv          融合基因预测结果
#    star-fusion.fusion_predictions.abridged.tsv 简化版结果
```

> 桥接 native 驱动：`python main.py detect --genome_lib_dir /path/to/CTAT_resource_lib --left_fq ../reads_1.fastq.gz --right_fq ../reads_2.fastq.gz --output_dir . --CPU 8`
> （驱动自动注入 `--CPU`）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有 star-fusion），直接拉取
官方镜像运行工具本体；`main.py` 驱动在宿主机跑。STAR-Fusion 主程序为 Perl 脚本，另有官方 GitHub 源码
（clone + make）作为并列的宿主安装路线。

### 1. Conda（包管理器安装）

```bash
mamba create -n star-fusion-native -c conda-forge -c bioconda star-fusion=1.15.1
conda activate star-fusion-native
STAR-Fusion --version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `star-fusion`，无 conda 时
> 走官方 GitHub 源码 clone + make 到 `~/software/star-fusion-<ver>` 并写 PATH；版本默认 1.15.1，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。
>
> 说明：Homebrew homebrew-core（`formulae.brew.sh/api/formula/star-fusion.json` → 404）与 brewsci/bio
> （`Formula/star-fusion.rb` → 404）均无公式，故不提供 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/star-fusion:1.15.1--hdfd78af_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/star-fusion:1.15.1--hdfd78af_1 \
    STAR-Fusion --genome_lib_dir /data/CTAT_resource_lib \
    --left_fq /data/reads_1.fastq.gz --right_fq /data/reads_2.fastq.gz \
    --output_dir /data/out --CPU 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull star-fusion.sif docker://depot.galaxyproject.org/singularity/star-fusion:1.15.1--hdfd78af_1
apptainer exec -B $PWD:/data star-fusion.sif \
    STAR-Fusion --genome_lib_dir /data/CTAT_resource_lib \
    --left_fq /data/reads_1.fastq.gz --right_fq /data/reads_2.fastq.gz \
    --output_dir /data/out --CPU 8
```

### 4. 官方 GitHub 源码（clone + make，并列备选）

```bash
git clone https://github.com/STAR-Fusion/STAR-Fusion.git ~/software/star-fusion-1.15.1/STAR-Fusion
cd ~/software/star-fusion-1.15.1/STAR-Fusion && make
# 产物即仓库内 STAR-Fusion 可执行脚本；缺 Perl 模块时建议改用 conda 备齐依赖
```

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；已装 STAR-Fusion 时做 --version 冒烟
```

## 官方实现登记（nextflow / snakemake，不建目录）

* **nf-core**：`modules/nf-core/star-fusion` 返回 404，官方无模块；Nextflow 场景需自定义或降级 native。
* **snakemake-wrappers**：`bio/star-fusion` 返回 404，官方无 wrapper；Snakemake 场景需自定义或降级 native。

## 版本

* star-fusion 1.15.1（bioconda::star-fusion=1.15.1，noarch）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/star-fusion:1.15.1--hdfd78af_1 / depot.galaxyproject.org；本地不再自建容器）
* 主程序为 Perl 脚本（GitHub master 内 `$VERSION=1.15.0`，bioconda 打包为 1.15.1）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/star-fusion/overview>
* **GitHub**：<https://github.com/STAR-Fusion/STAR-Fusion>
* **CTAT 资源库**：<https://github.com/NCIP/CTAT_genome_lib_build_DIR>
* **Docker**：`docker pull quay.io/biocontainers/star-fusion:1.15.1--hdfd78af_1`
* **Singularity**：<https://depot.galaxyproject.org/singularity/star-fusion%3A1.15.1--hdfd78af_1>
* 安装方式（本地）：`mamba create -n star-fusion -c conda-forge -c bioconda star-fusion=1.15.1`

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# star-fusion native Conda 环境配方
# 离线兜底：可另存为 star-fusion-native.yml 后 mamba env create -f star-fusion-native.yml；在线推荐上方 mamba create 直装命令
name: star-fusion-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - star-fusion=1.15.1
  - pyyaml>=6.0
  - pip
```
