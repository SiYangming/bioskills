# genomescope2 软件模块

> 汇总说明：本 README 说明 genomescope2（GenomeScope 2.0 / 官方 R 包 v1.0.0）的唯一本地实现
> （native）与官方 nf-core 登记；安装方式见下方各节，容器与 conda 信息记录于此。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/genomescope2/`（**扁平模块，无子目录**，2026-09 核实
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/genomescope2>）；pin
  `bioconda::genomescope2=2.1.0`（`environment.yml`）。执行：
  `nf-core modules install nf-core genomescope2`。
* **snakemake-wrappers**：`bio/genomescope2` **不存在**（2026-09 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/genomescope2> 返回 404）
  → Snakemake 场景用 native/main.py 兜底。
* **Homebrew**：homebrew-core（`formulae.brew.sh/api/formula/genomescope2.json` 404）与
  brewsci/bio（`Formula/genomescope2.rb` 404）两源均无公式（2026-09 核实）→ README 不登记 brew 块。

> 官方渠道已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉官方镜像
> 运行工具；`native/` 不维护 Dockerfile/Apptainer.def。

***

## native 实现

# genomescope2 / native — k-mer 基因组评估驱动（v1.0.0）

GenomeScope 2.0 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对照文档
`docs/04.md`（211-295 行）。

## 功能

| 子命令   | 命令                                                                                                | 作用                        |
| ----- | ------------------------------------------------------------------------------------------------- | ------------------------- |
| `run` | `genomescope.R -i <histo> -o <outdir> -k <k> [-p <ploidy>] [-l <lambda>] [-n <prefix>] [-m <max_kmercov>]` | k-mer 直方图 → 基因组大小/杂合度/重复估计 |

## 用法

```bash
# CLI 直跑（-p 1 单倍体 / -p 2 二倍体）
python main.py run -i mer_counts.histo -o genomescope -k 21 -p 1 --report genomescope.out
python main.py run -i mer_counts.histo -o genomescope -k 21 -p 2 -l 45 -m 1000

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（GenomeScope 为单线程 R 脚本，
`--threads` 仅保留契约、不注入）。

## 实战示例：k-mer 基因组评估

GenomeScope 2.0 用多倍体感知混合模型从 k-mer 直方图估计基因组特征，是组装前 survey 的标准工具；
输入直方图通常由 Jellyfish 产出（见 `modules/jellyfish`）。以下为文档给出的典型用法；等价能力
由 `native/main.py` 的 `run` 子命令提供（见上「用法」）。

```bash
mkdir -p genomescope2.0 && cd genomescope2.0
ln -s /path/to/FastUniq/illumina.?.fastq ./

# 1. jellyfish 计数 + 生成直方图（-C 计数互补链；-m 21 k-mer 长度；-s 100000000 hash 大小）
jellyfish count -C -m 21 -s 100000000 -t 4 -o mer_counts.jf *.fastq
jellyfish histo -t 4 mer_counts.jf > mer_counts.histo

# 2. GenomeScope 2.0 评估（-i 直方图；-o 输出目录；-k 21 k-mer 长度；-p 1 单倍体）
genomescope.R -i mer_counts.histo -o genomescope -k 21 -p 1 > genomescope.out
# 二倍体用 -p 2；报告与拟合图输出到 genomescope/ 目录
```

### 参数说明

| 参数   | 说明                            |
| ---- | ----------------------------- |
| `-i` | 输入 k-mer 计数直方图（jellyfish histo 产出） |
| `-o` | 输出目录                          |
| `-k` | k-mer 长度（与建直方图时一致）            |
| `-p` | 倍性（1=单倍体 / 2=二倍体；支持至 6）      |
| `-l` | 平均 k-mer 覆盖度初始猜测（可选）          |
| `-n` | 输出文件前缀（可选）                    |
| `-m` | 过滤高频率 k-mer 的覆盖度上限（可选）        |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行
工具；`main.py` 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
# conda 安装自动包含 jellyfish 依赖（无需单独安装 jellyfish）
# 注：bioconda 现行包版本为 2.1.0（无 1.0.0；文档的 v1.0.0 为官方 GitHub R 包 tag，见 §4）
mamba create -n genomescope2 -c conda-forge -c bioconda genomescope2=2.1.0
conda activate genomescope2
which genomescope.R    # 断言
```

> brew 两源（homebrew-core / brewsci/bio）均无 genomescope2 公式（2026-09 核实 404），README 不登记 Homebrew 块。
>
> 一键安装也可直接运行 `native/install.sh`（有 conda/mamba 时建 `genomescope2` 环境，无 conda 时走
> 官方 R 包源码路线 `--method r`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/genomescope2:2.1.0--py313r44hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/genomescope2:2.1.0--py313r44hdfd78af_0 \
    genomescope.R -i /data/mer_counts.histo -o /data/genomescope -k 21 -p 2
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull genomescope2.sif docker://depot.galaxyproject.org/singularity/genomescope2:2.1.0--py313r44hdfd78af_0
apptainer run -B $PWD:/data -H /data genomescope2.sif \
    genomescope.R -i /data/mer_counts.histo -o /data/genomescope -k 21 -p 2
```

### 4. 官方 R 包源码（GitHub tag v1.0.0，文档目标版本）

```bash
# 安装 Jellyfish（k-mer 计数工具）
# 依赖 R + argparse + minpack.lm；genomescope.R 需在 PATH
R2=https://github.com/tbenavi1/genomescope2.0/archive/v1.0.0.tar.gz
curl -fSL -o genomescope2.0-1.0.0.tar.gz "$R2"
R CMD INSTALL --library=$HOME/.R_libs genomescope2.0-1.0.0.tar.gz
tar zxf genomescope2.0-1.0.0.tar.gz -C "$HOME/software"
ln -sf "$HOME/software/genomescope2.0-1.0.0/genomescope.R" "$HOME/software/bin/genomescope.R"
export PATH="$HOME/software/bin:$PATH"
genomescope.R -i mer_counts.histo -o genomescope -k 21 -p 1
```

## 测试

```bash
bash test/run_test.sh   # 合成直方图 + argv 构造验证；genomescope.R 未安装时跳过真实冒烟
```

## 版本

* 官方 R 包 **v1.0.0**（GitHub tag，文档目标）；bioconda / 容器现行版本为 **2.1.0**
* 构建路线：官方镜像 / conda 提供（quay.io/biocontainers/genomescope2 / depot.galaxyproject.org）
* nf-core `genomescope2` pin bioconda::genomescope2=2.1.0（与容器版本一致）

***

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/genomescope2/overview>
* **官方仓库（R 包源码）**：<https://github.com/tbenavi1/genomescope2.0>（tag v1.0.0）
* **Docker**：`docker pull quay.io/biocontainers/genomescope2:2.1.0--py313r44hdfd78af_0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/genomescope2%3A2.1.0--py313r44hdfd78af_0>
* 安装方式（本地）：`mamba create -n genomescope2 -c conda-forge -c bioconda genomescope2=2.1.0`
  （或 `bash native/install.sh`）
