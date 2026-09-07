# riboss 软件模块

> 汇总说明：RiboSS（0.46）为 Python 包（无独立 CLI 二进制），本模块把稳定函数入口封装为原子
> 子命令（委托 `native/run_riboss.py`）；安装方式见「环境安装」，容器与 conda 链接见文末。

***

## native 实现

# riboss / native — python 驱动的长读+核糖体图谱翻译事件发现

RiboSS 0.46（Lim CS et al., Brief Bioinform 2025；<https://github.com/lcscs12345/riboss>）的本地
自包含实现（`source_type: custom`、`type: native`）。上游以 Python 包分发，官方用法为
conda env + Jupyter/脚本调用函数；本模块把文档化函数入口包装成 CLI 原子子命令。

## 功能

| 子命令 | 上游函数 | 作用 |
| ---- | ---- | ---- |
| `translate` | `riboss.orfs.translate` | 基础翻译（三帧，标准密码子表）快速自检 |
| `orf_finder` | `riboss.orfs.orf_finder` | 依注释（GTF/GFF3/BED/genePred）+ 转录本 FASTA 预测真核 ORF（m/u/d/oORF），输出 `<ann.stem>.orf_finder.pkl.gz`、`.transcripts.fa`、`.cds_range.txt` |
| `transcriptome_assembly` | `riboss.wrapper.transcriptome_assembly` | StringTie 长读 / 长短读混合参考引导组装（输出 .gtf/.bed/.transcripts.fa） |

完整「翻译潜力比较（boss）→ BED12/genePred/bigGenePred 轨道」流程见论文 notebooks
（<https://github.com/lcscs12345/riboss_paper>）；本模块先落地上述原子入口。

## 用法

```bash
# CLI 直跑
python main.py translate ATGGTCTGA                     # → MV（环境自检）
python main.py orf_finder --annotation ann.gtf --tx tx.fa --outdir orf_out \
    --start-codons ATG,CTG,GTG,TTG
python main.py transcriptome_assembly --superkingdom Eukaryota \
    --genome genome.fa --long-reads long.bam --threads 8 --outdir asm \
    --short-reads short.bam --strandness rf --annotation ann.gtf

# 也可直接调用执行器（等价）
python run_riboss.py translate ATGGTCTGA

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

`transcriptome_assembly` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：Ribo-seq 翻译事件发现（长读整合）

以下对应论文（bbaf164）核心工作流的关键步骤；等价能力由 `native/main.py` 的
`transcriptome_assembly` / `orf_finder` 子命令提供（见上「用法」）。

### 1. 环境自检（安装是否正确）

```bash
python main.py translate ATGGTCTGA     # 输出 MV 即 riboss 可用
```

### 2. 转录组参考引导组装（长读 / 混合）

```bash
python main.py transcriptome_assembly \
    --superkingdom Bacteria \
    --genome genome.fa \
    --long-reads direct_rna.bam \
    --short-reads rna_seq.bam --strandness rf \
    --annotation ref.gtf --threads 16 --outdir tx_assembly
# 产物：tx_assembly/*.gtf + *.transcripts.fa（供 orf_finder / bedtools getfasta）
```

### 3. ORF 预测（真核三帧候选 ORF）

```bash
# annotation 支持 GTF/GFF3/BED/genePred（内部经 UCSC gtfToGenePred/genePredToBed 统一）
python main.py orf_finder --annotation ref.gtf \
    --tx tx_assembly/xxx.transcripts.fa --outdir orf_out
# 产物：orf_out/xxx.orf_finder.pkl.gz（下游 boss/轨迹转换的输入 DataFrame）
```

### 4. 后续（翻译潜力比较与轨迹导出）

`riboss.riboss` 的 `boss()` / `base_to_bedgraph()` / `orfs_to_biggenepred()` 完成非规范 ORF
相对规范 ORF 的翻译潜力统计与 BED12/genePred/bigGenePred 输出（需 RPF 比对 + ribomap
riboprof 结果），用法以论文 notebooks 为准——本模块当前以 translate / orf_finder /
transcriptome_assembly 三个原子入口覆盖组装与 ORF 预测主链。

### 5. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--superkingdom` | 组装物种域：Archaea / Bacteria / Eukaryota（决定 junction 覆盖度） |
| `--strandness` | `rf`=fr-firststrand；`fr`=fr-secondstrand（`--short-reads` 混合时使用） |
| `--start-codons` | orf_finder 起始密码子（逗号分隔；默认 ATG,CTG,GTG,TTG，按丰度降序） |
| `--ncrna` | orf_finder 保留非编码 RNA 转录本（默认剔除） |

## 环境安装（官方镜像优先；本软件无官方 biocontainer → 社区镜像/conda/自建配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**无** riboss →
按查找规则登记替代渠道：conda（YangmingSi 个人频道，配方即上游 environment.yml 依赖集）+
quay.io/bioinfortools 社区镜像 + 自建配方（`native/Dockerfile`）。

### 1. Conda / brew（包管理器安装）

```bash
# conda（YangmingSi 频道；依赖自动带入，含 bedtools/bowtie2/star/salmon 等）
mamba create -n riboss -c conda-forge -c bioconda -c YangmingSi riboss=0.46
conda activate riboss
python -c 'from riboss.orfs import translate; assert translate("ATGGTCTGA")=="MV"'   # 断言
```

> 一键安装也可直接运行 `bash native/install.sh`（仅 conda 路线——依赖链重且无官方 release
> 二进制；用法：`bash native/install.sh --help`）。Homebrew 无 riboss 公式
> （`formulae.brew.sh/api/formula/riboss.json` 404），故不登记 brew 块。

### 2. Docker（社区镜像 + 自建）

```bash
# 社区镜像（bioinfortools；tag 0.46 与上游 __version__ 一致）
docker pull quay.io/bioinfortools/riboss:0.46
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/bioinfortools/riboss:0.46 \
    python -c 'from riboss.orfs import translate; print(translate("ATGGTCTGA"))'

# 或本地自建（native/Dockerfile：miniconda 底座 + 上游 environment.yml + pip install -e .）
docker build -t riboss:0.46 modules/riboss/native/
```

### 3. Apptainer / Singularity

```bash
# bioinfortools 无 galaxyproject 预构建 sif，从 quay 镜像直接转换即可
apptainer pull riboss.sif docker://quay.io/bioinfortools/riboss:0.46
apptainer run -B $PWD:/data -H /data riboss.sif \
    python -c 'from riboss.orfs import translate; print(translate("ATGGTCTGA"))'
```

### 4. 源码部署（git + 官方 environment.yml，仅 Linux 官方支持）

上游无编译资产（README 官方仅支持 Linux）；依赖链由 conda 官方 `environment.yml` 提供：

```bash
git clone https://github.com/lcscs12345/riboss.git ~/software/riboss-0.46
cd ~/software/riboss-0.46
conda env create -f environment.yml          # 依上游配方建 env（名称 riboss）
conda activate riboss
# 安装包本体（editable）并把附带的 riboprof 可执行放入 env bin
cp bin/riboprof "$(dirname "$(which python)")"; chmod +x "$(dirname "$(which python)")/riboprof"
python -m pip install -e . --no-deps
python -c 'from riboss.orfs import translate; assert translate("ATGGTCTGA")=="MV"'   # 断言
```

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；riboss 环境可用时真实回归 translate
```

## 版本

* riboss 0.46（上游 `setup.py` / `riboss/__init__.py` `__version__`；YangmingSi conda 包与
  bioinfortools 镜像 tag 均 0.46）
* 无官方 biocontainer（quay.io/biocontainers/riboss 不存在）→ 依赖经 conda（YangmingSi 包）/
  社区镜像（bioinfortools）/ 自建配方（native/Dockerfile）提供
* nf-core / snakemake-wrappers 均无 riboss 官方子模块（2026-09 在线核实 404）
* 上游 README 官方仅支持 Linux（Miniforge + conda env）；macOS 直装可能遇依赖缺失

## 历史留存

* `linux-64/` conda 构建配方已归位至 `native/conda-recipe/linux-64/meta.yaml`
  （重建 YangmingSi 频道 riboss 包用；其源码 URL 指向 SiYangming/riboss tag v0.46）。
* 原 `linux-64/config.yml`（运行参数示例：输入输出路径 / 分析 / 可视化 / 日志配置）归位至
  `native/config.yml`，为项目自定义示例配置（非上游文件），可按实际分析调整。
* `Dockerfile`（continuumio/miniconda3 底座 + 上游 environment.yml + `pip install .` + 清理）归位至
  `native/Dockerfile`；该配方保留 conda 路线（python 重依赖、非 apt 可解），运行务必加
  `-u $(id -u):$(id -g)`。

## 容器与 Conda 链接

* **GitHub（上游）**：<https://github.com/lcscs12345/riboss>
* **conda（YangmingSi 频道）**：<https://anaconda.org/channels/YangmingSi/packages/riboss/overview>
* **Docker（社区）**：`docker pull quay.io/bioinfortools/riboss:0.46`
* **自建配方**：`native/Dockerfile` + conda recipe（`native/conda-recipe/`）+ 示例配置（`native/config.yml`）
* 安装方式（本地）：`mamba create -n riboss -c conda-forge -c bioconda -c YangmingSi riboss=0.46`
  或 `bash native/install.sh`
