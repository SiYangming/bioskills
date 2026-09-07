# transdecoder 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# transdecoder / native — 自包含 ORF 预测驱动

**TransDecoder**（转录本 CDS 预测）的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包 `transdecoder=5.7.1` 提供两个二进制：**`TransDecoder.LongOrfs`** 与 **`TransDecoder.Predict`**。

## 功能

TransDecoder用于从转录本序列中识别开放阅读框（ORF）和预测编码区域的工具，常与 PASA、Trinity 等转录组分析工具配合使用。

* `longorfs`：提取候选最长 ORF → 生成 `<prefix>.transdecoder_dir/` 中间目录（longest\_orfs.pep/cds/gff3）

  `TransDecoder.LongOrfs -t <fasta> -O <dir> [--gene_trans_map <gtm>] [-m <aa>] [-G <code>] [-S] [--complete_orfs_only]`

* `predict`：基于序列组成模型预测最终 CDS → 输出 `<prefix>.transdecoder.{pep,cds,gff3,bed}`

  `TransDecoder.Predict -t <fasta> -O <dir> [--retain_pfam_hits] [--retain_blastp_hits] [--single_best_only] [--no_refine_starts] --cpu <N>`

* 自动解压 `.gz` 输入、自动注入线程（`--cpu`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py longorfs -t transcripts.fa -O out --min-protein-length 50 --genetic-code Universal --strand-specific --complete-orfs-only
python main.py predict  -t transcripts.fa -O out --retain-pfam-hits pfam.domtblout --retain-blastp-hits blastp.outfmt6 --no-refine-starts --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `longorfs` / `predict` 均支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：Trinity 转录本 ORF 预测（简单 / 同源搜索模式）

TransDecoder 承接 Trinity 无参组装（或 PASA 注释管线）的转录本：先 `LongOrfs` 按 6 读码框提取候选最长 ORF，再 `Predict` 以序列组成模型（+同源证据）预测最终 CDS。等价能力由 `native/main.py` 的 `longorfs` / `predict` 子命令提供（见上「用法」）；以下为原生 CLI 直接调用。

### 1. 简单模式（仅序列组成模型）

```bash
# 提取部分转录本快速测试（亦可全量输入）
perl -e 'while (<>) { $num ++ if m/^>/; last if $num > 200; print; }' transcripts.fasta > test.fa

# 第一步：六框翻译，提取候选最长 ORF（-m 最小蛋白长度）
TransDecoder.LongOrfs -t test.fa -m 100

# 第二步：序列组成模型打分，输出最终 CDS
TransDecoder.Predict -t test.fa
```

### 2. 同源搜索模式（推荐：保留 Pfam / BlastP 证据）

```bash
# ① LongOrfs 后取候选蛋白并清理序列 ID
perl -pe 's/^>(\S+).*/>$1/' transcripts.fasta.transdecoder_dir/longest_orfs.pep > longest_orfs.pep

# ② 蛋白同源搜索（-outfmt 6；超大库可用 diamond 加速）
blastp -query longest_orfs.pep -db uniprot_sprot \
    -max_target_seqs 1 -outfmt 6 -evalue 1e-5 -num_threads 4 > blastp.outfmt6

# ③ Pfam 结构域搜索
hmmscan --cpu 4 --domtblout pfam.domtblout Pfam-A.hmm longest_orfs.pep

# ④ 保留有同源证据的 ORF，去除假阳性
TransDecoder.Predict -t transcripts.fasta \
    --retain_pfam_hits pfam.domtblout \
    --retain_blastp_hits blastp.outfmt6
```

### 3. 预测序列名格式

`*.transdecoder.pep/cds/gff3/bed` 与中间目录 `*.transdecoder_dir/` 见上文「功能」，序列头示例：

```
TRINITY_DN_c115_g5_i1|m.1 type:complete len:300
├── TRINITY_DN_c115_g5_i1：原始转录本 ID
├── m.1：ORF 编号
├── type:complete：ORF 类型（complete / internal / 5prime_partial / 3prime_partial）
└── len:300：ORF 长度（氨基酸数）
```

### 4. 参数说明

| 参数                     | 说明                                            |
| ---------------------- | --------------------------------------------- |
| `-t <fasta>`           | 输入转录本序列（LongOrfs 与 Predict 用同一输入）             |
| `-m <aa>`              | 最小蛋白长度（官方默认 100；真菌等建议 50-100）                 |
| `--retain_pfam_hits`   | 保留有 Pfam 结构域命中的 ORF（hmmscan `--domtblout` 输出） |
| `--retain_blastp_hits` | 保留有蛋白同源命中的 ORF（blastp `-outfmt 6` 输出）         |

> 建议结合 Pfam / BlastP 同源证据提高预测准确性；链特异性测序需保证转录本序列方向正确后再预测。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑（容器内只含 transdecoder，无 python 驱动）。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n transdecoder-native -c bioconda -c conda-forge transdecoder
conda activate transdecoder-native
TransDecoder.LongOrfs --version       # 验证
# 或用 Homebrew（macOS / Linux；transdecoder 公式在 brewsci/bio tap，需先添加 tap）

# brew 版本：brewsci/bio/transdecoder 6.0.0（brew info 确认；较 meta 登记的 5.7.1 更新，本模块

#   native/流程 pin 5.7.1，需与登记版本一致时建议以 conda/environment.yml 为准）

brew tap brewsci/bio     # 首次使用需要
brew install transdecoder
TransDecoder.LongOrfs --version    # 断言（公式安装的二进制名）
```

> 快速创建亦可 `mamba create -n transdecoder-native -c conda-forge -c bioconda transdecoder=5.7.1`；完整离线配方（含 python / pyyaml）见文末「Conda 环境」节。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/transdecoder:6.0.0--pl5321hdfd78af_0    # bioconda 最新 build（tag 见文末「容器与 Conda 链接」）
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/transdecoder:6.0.0--pl5321hdfd78af_0 \
    TransDecoder.LongOrfs -t /data/transcripts.fa -O /data/out
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/transdecoder:6.0.0--pl5321hdfd78af_0 \
    TransDecoder.Predict -t /data/transcripts.fa -O /data/out --cpu 8
```

容器内为原生工具入口（官方镜像内只含 transdecoder，main.py 驱动在宿主机运行）；本模块 native / 流程 pin `transdecoder=5.7.1`，需要 Schema/自省/参数注入时在**宿主机**（conda env 装 transdecoder 5.7.1，见上 1.Conda）运行 `python main.py <subcommand> ...`。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换；等价直链见文末「容器与 Conda 链接」）：

```bash
apptainer pull transdecoder.sif docker://depot.galaxyproject.org/singularity/transdecoder:6.0.0--pl5321hdfd78af_0
apptainer run -B "$PWD":/data -H /data transdecoder.sif \
    TransDecoder.LongOrfs -t /data/transcripts.fa -O /data/out
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

* **GitHub release**：<https://github.com/TransDecoder/TransDecoder/releases>

* **文档**：<https://github.com/TransDecoder/TransDecoder/wiki>

官方 release 仅发 tag、无预编译资产，分发 tag 源码归档（纯 Perl 实现，解压即用、无需编译；运行时依赖 perl，blast+/hmmer 可选）。仓库布局以官方为准：根为主入口 `TransDecoder`，分阶段工具在 `util/`（`TransDecoder.LongOrfs` / `TransDecoder.Predict`）：

```bash
# 下载 v6.0.0 源码归档（release 列表见 https://github.com/TransDecoder/TransDecoder/releases；等价方式：git clone https://github.com/TransDecoder/TransDecoder.git）
wget https://github.com/TransDecoder/TransDecoder/archive/refs/tags/TransDecoder-v6.0.0.tar.gz -P ~/software/
cd ~/software && tar zxf TransDecoder-v6.0.0.tar.gz
mv TransDecoder-TransDecoder-v6.0.0 TransDecoder-v6.0.0   # GitHub archive 顶层目录名 <repo>-<tag>
# 主入口在根目录，分阶段工具在 util/ —— 一并加入 PATH
echo 'export PATH=$PATH:~/software/TransDecoder-v6.0.0:~/software/TransDecoder-v6.0.0/util' >> ~/.bashrc
source ~/.bashrc

# 验证安装
TransDecoder.LongOrfs --version
TransDecoder.Predict --version
```

## 测试

```bash
bash test/run_test.sh   # 无需真实转录本 FASTA；工具未装时退化为 argv 构造验证
```

## 版本

* transdecoder 5.7.1（bioconda::transdecoder=5.7.1，二进制 TransDecoder.LongOrfs / TransDecoder.Predict）

* 提供方式：官方镜像 / conda 提供（quay.io/biocontainers/transdecoder / depot.galaxyproject.org；宿主机安装用 mamba/conda 装 bioconda transdecoder=5.7.1）

## 历史留存

`snakemake/` 规则配套的同目录 wrapper 脚本（snakemake.shell + docker\_wrapper 分派）；正式入口为 `main.py`。

* `transdecoder_longorfs.py` — TransDecoder.LongOrfs wrapper（同目录，供 transdecoder\_longorfs.smk 使用）

* `transdecoder_predict.py` — TransDecoder.Predict wrapper（同目录，供 transdecoder\_predict.smk 使用）

## 单元测试（test/unit/）

`test/unit/` 存放单元测试（test\_transdecoder\_longorfs.py / test\_transdecoder\_predict.py + common.py/conftest.py），供 pytest 回归；`test/run_test.sh` 为技能自带的最小回归。

***

## snakemake 实现

# transdecoder / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 虽有 `bio/transdecoder/{longorfs,predict}`，但本目录提供
自维护实现（`source_type: custom`、`type: snakemake_local`），
用于本地定制 / 与历史流程行为对齐的场景。

## 规则文件

* `transdecoder_longorfs.smk` — `rule transdecoder_longorfs`：转录本 FASTA → `<outdir>/longorfs/`
  （候选最长 ORF；产物含 `<fa>.transdecoder_dir/longest_orfs.{pep,gff3,cds}`）

* `transdecoder_predict.smk` — `rule transdecoder_predict`：以 longorfs 产物为输入 → `<outdir>/predict/`
  （最终 CDS：`<fa>.transdecoder.{pep,gff3,cds,bed}`）

两规则均为 config 驱动、单样本通用（td2 式样板），不依赖 workflow 的 `SAMPLES` / `{sample}` 层级；
执行指令用同目录 `script:` wrapper（`transdecoder_longorfs.py` / `transdecoder_predict.py`，经共享
`modules/docker_wrapper.py` 按 `exec_mode` 三模式分派）；`conda:` 用同目录相对名 `"transdecoder.yaml"`。

config 契约（均有默认；独立运行时用 `--config` 覆盖）：

* `exec_mode`：conda(默认) | docker | native

* `transdecoder.docker_image` / `transdecoder.longorfs_bin` / `transdecoder.predict_bin`

* `transdecoder.gene_trans_map`（longorfs 可选）、`transdecoder.retain_pfam_hits` / `retain_blastp_hits`（predict 可选）

* `transdecoder.longorfs_extra_params` / `transdecoder.predict_extra_params`

* `transdecoder_input_fasta`（明文 FASTA）/ `transdecoder_outdir` / `threads`

## 用法

```python
# Snakefile 中
include: "modules/transdecoder/snakemake/transdecoder_longorfs.smk"
include: "modules/transdecoder/snakemake/transdecoder_predict.smk"
# rule all:
#     input: os.path.join(config["transdecoder_outdir"], "predict")
```

```bash
# 独立运行（longorfs 示例；predict 需先有 longorfs 产物）
snakemake -s modules/transdecoder/snakemake/transdecoder_longorfs.smk \
    --config transdecoder_input_fasta=transcripts.fa transdecoder_outdir=td_out --cores 4 --use-conda
```

## 依赖环境

规则内 `conda: "transdecoder.yaml"`（同目录，已随规则交付）：

```yaml
# transdecoder.yaml
channels: [conda-forge, bioconda]
dependencies:
  - transdecoder=5.7.1
  - perl
  - parallel
```

## 与其它实现的关系

* 官方 wrapper（snakemake-wrappers `v3.13.0/bio/transdecoder/{longorfs,predict}`，登记于软件级 `meta.yaml` / README，不建本地目录）亦可作为 Snakemake 路径

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# transdecoder native Conda 环境配方
# 离线兜底：可另存为 transdecoder-native.yml 后 mamba env create -f transdecoder-native.yml；在线推荐上方 mamba create 直装命令
# 说明：transdecoder 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：官方镜像（quay.io/biocontainers/transdecoder），本地不再自建 Dockerfile / Apptainer.def。
# 环境：transdecoder=5.7.1 + perl + parallel。
name: transdecoder-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - transdecoder=5.7.1    # 提供二进制 TransDecoder.LongOrfs / TransDecoder.Predict
  - perl                  # TransDecoder 运行时依赖
  - parallel              # LongOrfs 内部并行依赖（GNU parallel）
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/transdecoder/overview>

* **Docker**：`docker pull quay.io/biocontainers/transdecoder:6.0.0--pl5321hdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/transdecoder%3A6.0.0--pl5321hdfd78af_0>

* 安装方式（本地）：`mamba create -n transdecoder -c conda-forge -c bioconda transdecoder=6.0.0`

