# htseq 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09 逐渠道核实）。
> HTSeq 是处理高通量测序数据的 Python 库，命令行工具 `htseq-count` 从比对结果（SAM/BAM）与参考注释（GTF/GFF）计算基因表达量。

***

## native 实现

# htseq / native — HTSeq / htseq-count 自包含驱动

HTSeq 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对齐官方 htseq-count 与
教学文档「3.13 HTSeq」及「7.6 HTSeq 表达量计算」。

## 功能

HTSeq是一个灵活的Python库，用于从比对结果中计算基因表达量。htseq-count是其最常用的命令行工具。

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `count` | `htseq-count -f <fmt> -r <order> -s <strand> [-a N] -t exon -i gene_id [-m mode] [-o <samout>] <aln> <gff>` | 从比对结果计算基因表达量 |

参数说明：

| 参数 | 说明 |
| --- | --- |
| `-f` | 输入文件格式，`sam` 或 `bam` |
| `-r` | 排序方式，`name` 或 `pos`（需与输入一致） |
| `-s` | 链特异性，`yes`（正向）/ `no`（非链特异）/ `reverse`（反向） |
| `-a` | 最小比对质量，低于该值的比对被忽略 |
| `-t` | 计数特征类型，默认 `exon` |
| `-i` | 分组属性，默认 `gene_id`（转录本水平可用 `transcript_id`） |
| `-m` | 计数模式，`union` / `intersection-strict` / `intersection-nonempty` |
| `-o` | 输出带 HTSeq 注释的 SAM/BAM（可选） |

> `htseq-count` 为**单线程**工具，无 `--threads` 透传（驱动接受 `--threads` 仅为接口对齐）。
> 计数结果默认写 stdout；驱动可用 `--output` 落盘（等价教学文档示例的 `> counts.txt`）。

## 用法

```bash
# CLI 直跑（文档 7.6 示例参数）
python main.py count -f bam -r pos -s no -a 10 -t exon -i gene_id accepted_hits.bam genome.gtf --output counts.txt
python main.py count -f sam -r pos -s reverse -m intersection-strict accepted_hits.sam genome.gff --output counts.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 对 htseq-count 不生效）。

## 实战示例：逐样本 htseq-count → 合并表达量矩阵

以下为有参转录组（HISAT2 比对后）典型定量用法（源自教学文档 3.13 / 7.6 章节，路径改写为无硬编码的
通用形式）；等价能力由 `native/main.py` 的 `count` 子命令提供（见上「用法」）。

### 1. 逐样本计数

```bash
mkdir -p htseq_out && cd htseq_out

# 对每个样本单独计数（-r 排序方式需与 BAM 实际排序一致；HISAT2 默认按 pos/坐标排序）
for bam in ../hisat2/*.bam
do
    sample=$(basename $bam .bam)
    htseq-count -f bam -r pos -s no -a 10 -t exon -i gene_id $bam ../genome.gtf > ${sample}.counts.txt
done
```

### 2. 合并表达量矩阵

```bash
# 教学文档用 htseq_outs2matrix.pl 合并；此处用 POSIX 工具等价实现（每个 counts.txt 含 5 行 __ 统计行，需剔除）
paste <(cut -f1 A.counts.txt) \
      <(for f in A B C D E F G; do cut -f2 ${f}.counts.txt; done) > raw_counts.matrix
# 或先剔除 __no_feature/__ambiguous/... 统计行再合并
```

### 3. 桥接 native 驱动

```bash
# 等价（驱动写文件而非重定向）
python main.py count -f bam -r pos -s no -a 10 -t exon -i gene_id ../hisat2/sample.bam ../genome.gtf --output sample.counts.txt
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有 htseq），直接拉取官方镜像
运行工具本体；`main.py` 驱动在宿主机跑。官方另有官方 PyPI 发行（`pip install HTSeq`，含预编译 wheel），
作为宿主安装的并列路线。

### 1. Conda / pip（包管理器安装）

```bash
mamba create -n htseq-native -c conda-forge -c bioconda htseq=2.1.2
conda activate htseq-native
htseq-count --version   # 断言
```

```bash
# 或用官方 PyPI 发行（venv 隔离安装，requires_python>=3.10）
python3 -m venv ~/software/htseq-2.1.2
~/software/htseq-2.1.2/bin/pip install HTSeq==2.1.2
~/software/htseq-2.1.2/bin/htseq-count --version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 bioconda 环境 `htseq`，无 conda 时走
> 官方 PyPI 装到 `~/software/htseq-<ver>` 独立 venv 并写 PATH；版本默认 2.1.2，与下方 `software_versions`
> 对齐。用法：`bash native/install.sh --help`）。
>
> 说明：Homebrew homebrew-core（`formulae.brew.sh/api/formula/htseq.json` → 404）与 brewsci/bio
> （`Formula/htseq.rb` → 404）均无公式，故不提供 brew 块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/htseq:2.1.2--py311h0e292b2_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/htseq:2.1.2--py311h0e292b2_3 \
    htseq-count -f bam -r pos -s no -a 10 -t exon -i gene_id /data/accepted_hits.bam /data/genome.gtf
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull htseq.sif docker://depot.galaxyproject.org/singularity/htseq:2.1.2--py311h0e292b2_3
apptainer exec -B $PWD:/data htseq.sif \
    htseq-count -f bam -r pos -s no -t exon -i gene_id /data/accepted_hits.bam /data/genome.gtf
```

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；已装 htseq-count 时做 --version 冒烟
```

## 官方实现登记（nextflow，不建目录）

* **nf-core**：`modules/nf-core/htseq/count`（2026-09 抓取目录 HTTP 200）。执行前请用
  `nf-core modules install htseq/count` 安装到项目自身目录；版本锚点 `bioconda::htseq=2.0.3`。
* **snakemake-wrappers**：`bio/htseq` 返回 404，官方无 wrapper；Snakemake 场景请降级 native。
* **版本差异**：native 2.1.2；nf-core 当前 pin **2.0.3**（相差一个 minor，详见 `meta.yaml software_versions`）。

## 版本

* htseq 2.1.2（bioconda::htseq=2.1.2；官方 PyPI `HTSeq==2.1.2`）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/htseq:2.1.2--py311h0e292b2_3 / depot.galaxyproject.org；本地不再自建容器）
* 与 nf-core 的 bioconda pin（2.0.3）存在一个 minor 差异（见上）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/htseq/overview>
* **官方文档**：<https://htseq.readthedocs.io/>
* **GitHub**：https://github.com/htseq/htseq
* **PyPI（官方发行）**：<https://pypi.org/project/HTSeq/>
* **Docker**：`docker pull quay.io/biocontainers/htseq:2.1.2--py311h0e292b2_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/htseq%3A2.1.2--py311h0e292b2_3>
* 安装方式（本地）：`mamba create -n htseq -c conda-forge -c bioconda htseq=2.1.2`

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# htseq native Conda 环境配方
# 离线兜底：可另存为 htseq-native.yml 后 mamba env create -f htseq-native.yml；在线推荐上方 mamba create 直装命令
name: htseq-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - htseq=2.1.2
  - pyyaml>=6.0
  - pip
```
