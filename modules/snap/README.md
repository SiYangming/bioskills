# snap 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；容器与 conda 环境信息记录于文末「容器与 Conda 链接」。
> 官方 nf-core / snakemake-wrappers 均无 SNAP 实现（2026-09 抓取 404，见「版本」），故仅登记 native。

***

## native 实现

# snap / native — 自包含 SNAP 训练 + 预测驱动

SNAP（KorfLab，`Semi-HMM-based Nucleic Acid Parser`）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

SNAP 是一个基于隐马尔可夫模型的基因预测工具，需要先进行训练。

SNAP 是 MAKER 支持的从头基因预测工具之一。

七个子命令对应 SNAP 训练 → 预测全链路：

| 子命令             | 命令                                            | 作用                                |
| --------------- | --------------------------------------------- | --------------------------------- |
| `gene_stats`    | `fathom <ann> <dna> -gene-stats`              | 统计训练集基因信息                          |
| `validate`      | `fathom <ann> <dna> -validate`                | 校验训练基因模型                          |
| `categorize`    | `fathom <ann> <dna> -categorize <window>`     | 按类别拆分基因模型                         |
| `export`        | `fathom <ann> <dna> -export <window> -plus`   | 导出训练数据（export.ann/export.dna）      |
| `forge`         | `forge <export.ann> <export.dna>`             | 由导出数据构建 HMM 参数                    |
| `hmm_assembler` | `hmm-assembler.pl <name> <params>`            | 生成 HMM 模型文件（stdout → `--output`）   |
| `predict`       | `snap <species.hmm> <genome.fasta>`           | 用训练模型预测基因（stdout → ZFF）           |

> SNAP 的 fathom/forge/snap 均为**单线程**程序；各子命令仍接受 `--threads` / `--tmpdir` 以保持接口一致（`--threads` 不向二进制透传）。

## 用法

```bash
# CLI 直跑
python main.py gene_stats genome.ann genome.dna
python main.py validate   genome.ann genome.dna
python main.py categorize genome.ann genome.dna -w 200
python main.py export     genome.ann genome.dna -w 200
python main.py forge      export.ann export.dna
python main.py hmm_assembler species params -o species.hmm
python main.py predict species.hmm genome.fasta -o snap_out.zff

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：训练 SNAP → 预测 → 转 GFF3

SNAP 需要先用高质量训练基因模型（如 AUGUSTUS 训练集）训练 HMM，再用模型预测。以下为典型流程；等价能力由 `native/main.py` 的 7 个子命令提供（见上「用法」）。

### 1. 训练 SNAP

```bash
mkdir -p snap && cd snap
ln -s ../augustus/training/ati.filter2.gff3 ../genome.fasta ./

# 将 GFF3 转为 SNAP 训练格式（EVM 附带脚本）
export PERL5LIB=$PERL5LIB:/opt/biosoft/EVM_r2012-06-25/PerlLib/
/opt/biosoft/EVM_r2012-06-25/OtherGeneFinderTrainingGuide/SNAP/gff3_to_SNAP_train.pl \
    ati.filter2.gff3 genome.fasta

# 统计 / 校验
fathom genome.ann genome.dna -gene-stats &> gene-stats.log
fathom genome.ann genome.dna -validate  &> validate.log

# 分类与导出训练数据
fathom genome.ann genome.dna -categorize 200
rm alt.* err.* olp.* wrn.*
fathom genome.ann genome.dna -export 200 -plus

# 构建 HMM 参数 -> 生成模型
mkdir params && cd params && forge ../export.ann ../export.dna && cd ..
hmm-assembler.pl species params > species.hmm
```

### 2. 运行预测

```bash
snap species.hmm genome.fasta > snap_out.zff

# 转换为 GFF3（EVM 附带脚本）
/opt/biosoft/EVM_r2012-06-25/OtherGeneFinderTrainingGuide/SNAP/SNAP_output_to_gff3.pl \
    snap_out.zff genome.fasta > snap.gff3
```

> **桥接**：上述命令等价于 `python main.py export ...` + `python main.py forge ...` + `python main.py hmm_assembler ...` + `python main.py predict ...`；坐标转换后处理仍用官方 Perl 脚本。

### 3. 参数说明

| 参数                        | 说明                       |
| ------------------------- | ------------------------ |
| `-gene-stats`             | 统计训练集基因信息                |
| `-validate`               | 校验基因模型（输出 OK/其它）         |
| `-categorize <window>`    | 分类窗口大小（教程用 200）          |
| `-export <window> -plus`  | 导出训练数据并包含侧翼序列            |
| `species.hmm`             | 训练好的 HMM 模型文件            |
| `snap <hmm> <genome>`     | 用模型预测，输出 ZFF 文本          |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。
SNAP 上游**不提供预编译二进制包**（仅 GitHub 源码），故本地安装走 conda；源码编译小节并列保留。

### 1. Conda（包管理器安装）

```bash
mamba create -n snap -c conda-forge -c bioconda snap=2013_11_29
conda activate snap
snap -help   # 验证（SNAP 无 --version 选项）
```

> ⚠️ bioconda 的 `snap` 是 KorfLab 基因预测 SNAP，**不是** Ubuntu 的 `snap` 包管理器。
> Homebrew 的 `snap` 公式（`Tool to work with .snap files`，snapcraft）同名异义，非本软件，故不登记 brew。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `snap`，无 conda 时从官方 GitHub 源码 `make` 编译到 `~/software/snap-<ver>` 并写 PATH；版本默认 2013_11_29，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/snap:2013_11_29--0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/snap:2013_11_29--0 \
    snap /data/species.hmm /data/genome.fasta > snap_out.zff
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull snap.sif docker://depot.galaxyproject.org/singularity/snap:2013_11_29--0
apptainer run -B $PWD:/data -H /data snap.sif snap /data/species.hmm /data/genome.fasta > snap_out.zff
```

### 4. 官方源码编译（并列保留）

官方源码仓库：<https://github.com/KorfLab/SNAP>（旧官网分发页 `korflab.ucdavis.edu/Software/` 当前不可达，2026-09 核实；GitHub 仓库无版本化 tag，源码编译为当前默认分支）。

```bash
# 下载源码并编译（无需 root，用户前缀安装）
tmp="$(mktemp -d)"
curl -fsSL https://github.com/KorfLab/SNAP/archive/refs/heads/master.tar.gz -o "$tmp/snap.tar.gz"
tar xzf "$tmp/snap.tar.gz" -C "$tmp"
cd "$tmp"/SNAP-master && make -j 4
mkdir -p ~/software/snap/bin
install -m 0755 snap fathom forge hmm-assembler.pl ~/software/snap/bin/
echo 'export PATH=$PATH:~/software/snap/bin' >> ~/.bashrc && source ~/.bashrc
snap -help   # 验证
```

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（SNAP 需真实基因组/模型，合成数据无法覆盖）
```

## 版本

* snap `2013_11_29`（bioconda::snap=2013_11_29；bioconda 另有 2017_03_01）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/snap / depot.galaxyproject.org；本地不再自建容器）
* 官方 nf-core module（`modules/nf-core/snap`）与 snakemake-wrappers（`bio/snap`）均无（2026-09 抓取 404）
* ⚠️ 注意与其他同名 `snap`（Ubuntu snapd / Homebrew snapcraft）区分

## 容器与 Conda 链接

* **GitHub**：https://github.com/KorfLab/SNAP
* **Bioconda 页面**：<https://anaconda.org/bioconda/snap>
* **Docker**：`docker pull quay.io/biocontainers/snap:2013_11_29--0`
* **Singularity**：<https://depot.galaxyproject.org/singularity/snap%3A2013_11_29--0>
* 安装方式（本地）：`mamba create -n snap -c conda-forge -c bioconda snap=2013_11_29`
