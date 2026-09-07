# riborf 软件模块

> 汇总说明：RibORF 2.0 为 perl 子脚本管线（无单一主程序），本模块以 perl 驱动各子命令；
> 安装方式见「环境安装」，容器与 conda 链接见文末。

***

## native 实现

# riborf / native — perl 驱动的 Ribo-seq 翻译 ORF 鉴定管线

RibORF 2.0（Ji et al., eLife 2015 / <https://github.com/zhejilab/RibORF>）的本地自包含实现
（`source_type: custom`、`type: native`）。软件本体为 `RibORF.2.0/` 下的 7 个 perl 子脚本，
`native/main.py` 按流水线子命令逐一调用（脚本经 PATH / `$RIBORF_HOME` 解析）。

## 功能

| 子命令 | perl 脚本 | 作用 |
| ---- | ---- | ---- |
| `remove_adapter` | `removeAdapter.pl` | 去除 3' 接头并过滤过短 read |
| `orfannotate` | `ORFannotate.pl` | 依转录本 genePred + 基因组注释候选 ORF（输出 candidateORF.genepred.txt/.fa） |
| `read_dist` | `readDist.pl` | 检查 RPF 5' 端在起止密码子附近分布（3-nt 周期性质控，输出图+表） |
| `offset_correct` | `offsetCorrect.pl` | 按 offset 参数文件校正 read 位置（A-site） |
| `riborf` | `ribORF.pl` | 用校正后 read 预测候选 ORF 翻译概率（f1/PME/f1max 特征，输出 pred/ROC/stat） |
| `merge_orf` | `mergeORF.pl` | 合并多次预测的重叠 ORF（多文件用 `~` 分隔） |

## 用法

```bash
# CLI 直跑（单条子命令；参数与上游 perl 脚本一一对应）
python main.py remove_adapter -f reads.fastq -a CTGTAGGCAC -o trimmed.fastq -l 15
python main.py orfannotate -g genome.fa -t ref.genePred -o orf_out -s ATG/CTG/GTG/TTG/ACG -l 6
python main.py read_dist -f reads.sam -g ref.genePred -o qc_out -d 28,29,30 -l 40 -r 70
python main.py offset_correct -r reads.sam -p offset.params.txt -o reads.corrected.sam
python main.py riborf -f reads.corrected.sam -c candidateORF.genepred.txt -o pred_out -p 0.7
python main.py merge_orf -f reads.corrected.sam -c pred1/retained.ORF.genepred.txt~pred2/retained.ORF.genepred.txt -o merge_out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：Ribo-seq 翻译 ORF 发现全流程

以下为 RibORF 2.0 官方协议（RibORF.2.0README.txt，本模块 native/ 目录内留有副本）的落地示例；
等价能力由 `native/main.py` 的对应子命令提供（见上「用法」）。

### 1. 数据与注释准备

* Ribo-seq reads（FASTQ）；基因组 FASTA；rRNA 序列；转录本注释 genePred（`gtfToGenePred` 由 GTF 转换）
* 建 rRNA / 基因组索引并比对（bowtie2 去 rRNA，tophat/STAR 比对转录组/基因组，产出 SAM）

### 2. 去接头 → 候选 ORF 注释

```bash
# 去 3' 接头（-a 取接头前 10nt；-l 最保守长 read 长度）
python main.py remove_adapter -f SRR1802146.fastq -a CTGTAGGCAC -o adapter.clean.fastq -l 15

# 候选 ORF（默认考虑 ATG/CTG/GTG/TTG/ACG 起始，最短 6nt；产物 candidateORF.genepred.txt/.fa）
python main.py orfannotate -g genome.fa -t gencode.v28.genePred.txt -o orf_annot
```

### 3. 周期性质控 → offset 校正 → 翻译 ORF 预测

```bash
# 质控：确认 ~30nt 主峰与 3-nt 周期性（高质量数据 1st 位 >50%）
python main.py read_dist -f SRR1802146.mapping.sam -g gencode.v28.genePred.txt -o qc_raw -d 28,29,30, -l 40 -r 70

# offset 校正：偏移参数文件两列（read 长度 / offset 距离，参考 readDist 图人工判读）
printf '28\t15\n29\t16\n30\t16\n' > offset.params.txt
python main.py offset_correct -r SRR1802146.mapping.sam -p offset.params.txt -o reads.corrected.sam

# 预测：orfReadCutoff(-r 支持 read 数) 与 predictPvalueCutoff(-p 概率阈值) 控制严格度
python main.py riborf -f reads.corrected.sam -c orf_annot/candidateORF.genepred.txt -o pred_out -l 6 -r 11 -p 0.7

# （可选）多次预测合并：-c 多文件用 ~ 分隔；产物 retained/filtered.ORF.genepred.txt
python main.py merge_orf -f reads.corrected.sam -c pred_a/retained.ORF.genepred.txt~pred_b/retained.ORF.genepred.txt -o merge_out
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-a / --adapter` | 3' 接头序列（推荐前 10nt），remove_adapter |
| `-s / --start-codons` | 起始密码子集合（`/` 分隔），orfannotate |
| `-d / --read-lengths` | 指定 RPF 长度（逗号分隔），read_dist（校正后置 `1`） |
| `-p / --offset-params` | offset 校正参数文件，offset_correct |
| `-r / --orf-read-cutoff` | 支持 read 数阈值，riborf |
| `-p / --predict-pvalue-cutoff` | 预测翻译概率阈值，riborf |

## 环境安装（官方镜像优先；本软件无官方 biocontainer → 社区镜像/conda/自建配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**无** riborf →
按查找规则登记替代渠道：conda（YangmingSi 个人频道）+ quay.io/bioinfortools 社区镜像 +
自建配方（`native/Dockerfile`，RibORF 依赖 perl/bowtie2/tophat/R-e1071 等，conda 打包最稳）。

### 1. Conda / brew（包管理器安装）

```bash
# conda（YangmingSi 频道；依赖自动带入 bowtie2/tophat/r-base/r-e1071/samtools/bedtools）
mamba create -n riborf -c conda-forge -c bioconda -c YangmingSi riborf=2.0
conda activate riborf
command -v ribORF.pl && perl -c "$(command -v ribORF.pl)"   # 断言
```

> 一键安装也可直接运行 `bash native/install.sh`（auto：有 conda/mamba → YangmingSi conda 包；
> 无 conda → git 部署 perl 脚本到 `~/software/riborf-2.0` 并写 PATH。用法：`bash native/install.sh --help`）。
> 源码部署亦可：`git clone https://github.com/zhejilab/RibORF.git` 并把 `RibORF.2.0/` 加入 PATH。

> Homebrew 无 RibORF 公式（`formulae.brew.sh/api/formula/riborf.json` 404），故不登记 brew 块。

### 2. Docker（社区镜像 + 自建）

```bash
# 社区镜像（bioinfortools；tag 2.1=含 shebang/执行权限修复的打包版，软件本体 2.0）
docker pull quay.io/bioinfortools/riborf:2.1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/bioinfortools/riborf:2.1 \
    perl /opt/riborf/RibORF.2.0/removeAdapter.pl -f /data/reads.fastq \
    -a CTGTAGGCAC -o /data/trimmed.fastq

# 或本地自建（native/Dockerfile：miniconda 底座 + 同上依赖 + 源码部署）
docker build -t riborf:2.0 modules/riborf/native/
```

### 3. Apptainer / Singularity

```bash
# bioinfortools 无 galaxyproject 预构建 sif，从 quay 镜像直接转换即可
apptainer pull riborf.sif docker://quay.io/bioinfortools/riborf:2.1
apptainer run -B $PWD:/data -H /data riborf.sif \
    perl /opt/riborf/RibORF.2.0/removeAdapter.pl -f /data/reads.fastq -a CTGTAGGCAC -o /data/trimmed.fastq
```

### 4. 源码部署（git，无 conda / docker 依赖）

上游无编译资产与 release tag（git master 即 2.0），脚本纯 perl 无需编译：

```bash
git clone --depth 1 https://github.com/zhejilab/RibORF.git ~/software/riborf-2.0/RibORF
echo 'export PATH=$PATH:~/software/riborf-2.0/RibORF/RibORF.2.0/' >> ~/.bashrc
source ~/.bashrc
perl -c "$(command -v ribORF.pl)"   # 断言（需已装 perl）
```

> 完整流程工具（bowtie2/tophat/R 等）请另配 conda 环境；source 路线仅部署 RibORF 本体。

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；perl+脚本可用时真实回归 remove_adapter
```

## 版本

* riborf 2.0（上游 git master；RibORF.2.0 目录为准；bioinfortools 镜像 tag 2.1 为打包修复版）
* 无官方 biocontainer（quay.io/biocontainers/riborf 不存在）→ 依赖经 conda（YangmingSi 包）/
  社区镜像（bioinfortools）/ 自建配方（native/Dockerfile）提供
* nf-core / snakemake-wrappers 均无 riborf 官方子模块（2026-09 在线核实 404）
* ⚠️ 许可证以上游 `RibORF.2.0/LICENSE` 为准（GPL-3.0-only）；native/conda-recipe 历史 meta 曾记 MIT，与上游不符，打包时需修正

## 历史留存

* 目录历史中的 `Dockerfile_RibORF_2_0`（裸源码部署）与 `Dockerfile_RibORF_2_1`（含 shebang 修复）——
  本模块保留较优的 2.1 版本并归位为 `native/Dockerfile`；2.0 版本能力相同仅缺 shebang 修复，不再重复维护。
* `linux-64/`、`osx-arm64/` 两套 conda 构建配方已归位至 `native/conda-recipe/{linux-64,osx-arm64}/meta.yaml`
  （用于重建 YangmingSi 频道 riborf 包）。
* 上游说明文档 `RibORF.2.0README.txt` 与许可证 `LICENSE` 保留在 `native/`（追溯协议步骤与授权）。

## 容器与 Conda 链接

* **GitHub（上游）**：<https://github.com/zhejilab/RibORF>
* **conda（YangmingSi 频道）**：<https://anaconda.org/channels/YangmingSi/packages/riborf/overview>
* **Docker（社区）**：`docker pull quay.io/bioinfortools/riborf:2.1`
* **自建配方**：`native/Dockerfile` + conda recipe（`native/conda-recipe/`）
* 安装方式（本地）：`mamba create -n riborf -c conda-forge -c bioconda -c YangmingSi riborf=2.0`
  或 `bash native/install.sh`
