# hisat2 软件模块

> 汇总说明：本 README 合并各实现（native / 官方 nf-core / 官方 snakemake-wrappers）的用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。官方实现（nf-core / snakemake-wrappers）在本仓库**不建源码目录**，其存在性、pin 与版本差异登记于 `meta.yaml.software_versions` 与下文「官方实现登记」节。

***

## native 实现

HISAT2 是基于图 FM-index（graph-based）的 RNA-seq 剪接比对器（C 程序，含 Python 辅助脚本）：`hisat2-build` 建立 HT2 索引（可加 `--ss` 剪接位点、`--exon` 外显子、SNP 等先验信息提升剪接比对），`hisat2` 做单端/双端比对并输出 SAM（`--dta` 输出兼容 stringtie 组装，`--rna-strandness` 声明链特异性文库）。官网：<http://daehwankimlab.github.io/hisat2/>；GitHub：<https://github.com/DaehwanKimLab/hisat2>。

基于 bioconda / brew（brewsci/bio）/ 官方源码的 Python 驱动包装：

* 子命令映射：`index` → `hisat2-build`（建索引）、`align` → `hisat2`（比对），直接构造真实命令并自动注入 `-p` 线程（默认 8，可 `--threads` 覆盖）与 `TMPDIR`
* `hisat2` SAM 默认输出 stdout（原生行为），可用 `-S/--output` 落盘
* `--dry-run` 仅构造并打印 argv（供降级回归，不需要 hisat2 二进制）
* 运行时需本地安装 `hisat2`（conda / brew / 官方源码编译任选，见「环境安装」）；二进制不在 PATH 时抛清晰错误

## CLI 用法示例

```bash
# 建索引（可先由 GTF 提取剪接位点/外显子：extract_splice_sites.py / extract_exons.py）
python main.py index genome.fa --index-base hg38 --splice-sites ss.txt --exon exons.txt
python main.py index genome.fa --index-base hg38 --threads 16

# 双端 RNA-seq 比对（--dta 供 stringtie；dUTP 文库 --rna-strandness RF）
python main.py align -x hg38 -1 s_R1.fq.gz -2 s_R2.fq.gz \
    --dta --rna-strandness RF --threads 16 -S out.sam

# 自省
python main.py --list-commands
python main.py --schema
```

## 实战示例（RNA-seq hisat2 → stringtie 标准流程）

以下为原生 HISAT2 CLI 的典型用法；等价能力由 `native/main.py` 的 `index` / `align` 子命令提供（见上「CLI 用法示例」）。

### 1. 多样本循环（比对 → 排序/转 BAM → stringtie 组装）

```bash
REF=genome.fa
# 0) 从 GTF 提取剪接位点/外显子并建索引（可含先验）
python3 $HISAT2_HOME/extract_splice_sites.py genes.gtf > ss.txt
python3 $HISAT2_HOME/extract_exons.py genes.gtf > exons.txt
hisat2-build -p 16 --ss ss.txt --exon exons.txt $REF hg38

# 1) 逐样本比对 + 排序（--dta 对 stringtie 必需）
for s in sampleA sampleB; do
  hisat2 -p 8 --dta --rna-strandness RF -x hg38 \
      -1 ${s}_R1.fastq.gz -2 ${s}_R2.fastq.gz \
  | samtools sort -@ 4 -O BAM -o ${s}.sorted.bam -
done
# 2) stringtie 组装（参考模块 stringtie）
stringtie -p 8 -G genes.gtf -o ${s}.gtf ${s}.sorted.bam
```

### 2. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-x <idxbase>` | HT2 索引 basename（`hisat2-build` 输出，不含 `.1.ht2` 后缀） |
| `-1/-2` | 双端 reads（可逗号多文件）；`-U` 单端 reads |
| `-S out.sam` | SAM 输出文件（缺省 stdout，可管道给 samtools） |
| `-p N` | 线程数（hisat2/hisat2-build 均支持；index 建议 16） |
| `--dta` | 输出兼容转录本组装（stringtie 官方推荐；等价 `--downstream-transcriptome-assembly`） |
| `--rna-strandness FR/RF/unstranded` | 链特异性（dUTP 链式文库为 RF；Illumina TruSeq 非链式可不加） |
| `--known-splicesite-infile` | align 时提供已知剪接位点（index 已含 --ss 时可省略） |
| `build --ss / --exon` | 建索引用剪接位点/外显子先验（GTF 提取，见上） |
| `build --snp <snps>` | 建索引用 SNP 先验（`hisat2_extract_snps_VCF.pl` 处理 VCF 后输入 → SNP 感知比对） |
| `--novel-splicesite-outfile` | 输出新剪接位点（找新 isoform 用） |
| `--dta-cufflinks` | 输出兼容 cufflinks 组装（stringtie 用 `--dta` 即可） |
| `--new-summary` | 新格式比对统计摘要（详细 per 分类计数） |
| `--summary-file <f>` | 统计摘要写文件（配合 `--new-summary`） |
| `--min-intronlen <n>` | 最小内含子长度（默认 20；下游 stringtie 常再限 20–50） |
| `--max-intronlen <n>` | 最大内含子长度（默认 500000；RNA-seq 常按物种限 4000–100000） |

> 上游 hisat2-2.2.x 官方推荐流程（hisat2-StringTie 组合）见 <https://ccb.jhu.edu/software/stringtie/>；hisat2 亦内置 hisatgenotype（基因分型，超出本模块范围）。

> 💡 **RNA-seq 比对要点**：RNA-seq 比对时建议提供基因注释文件（GTF）提取剪接位点
> 先验（`extract_splice_sites.py` → `hisat2-build --ss`），能显著提高比对效率与剪接
> 位点识别准确性（无注释物种才做 de novo 剪接发现）。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行 hisat2 二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n hisat2 -c conda-forge -c bioconda hisat2=2.2.3
conda activate hisat2
hisat2 --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；homebrew-core 无此公式，公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio
brew install hisat2
hisat2 --version   # 断言
# 注：brewsci/bio hisat2 公式基于官方 v2.2.2 源码构建（比 meta 登记的官方最新 2.2.3 低一版，以 formula 为准）
```

> 宿主机直跑 `python main.py index|align` 推荐用文末「Conda 环境」配方建环境（`name: hisat2-native`）。本模块不维护本地安装脚本：conda/brew/官方源码三条官方渠道见上/见下。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/hisat2:2.2.3--h8471819_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/hisat2:2.2.3--h8471819_1 \
    hisat2 -p 8 --dta -x /data/hg38 \
    -1 /data/s_R1.fq.gz -2 /data/s_R2.fq.gz > /data/out.sam
```

> 容器内即 hisat2 全套二进制（hisat2/hisat2-build/hisat2-inspect + 辅助脚本）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 hisat2）运行 `python main.py`。tag 全列表以 quay 页面为准。

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif（tag 与 quay 互通），直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull hisat2.sif docker://depot.galaxyproject.org/singularity/hisat2:2.2.3--h8471819_1
apptainer run -B $PWD:/data -H /data hisat2.sif \
    hisat2 -p 8 -x /data/hg38 -1 /data/s_R1.fq.gz -2 /data/s_R2.fq.gz > /data/out.sam
```

### 4. 二进制包安装（官方 release：源码编译）

hisat2 官方 release **无预编译资产**（v2.2.3 release 仅源码 tag 归档；官方 GitHub 提供 zip 源码包，`make` 编译，产物含 hisat2/hisat2-build/hisat2-inspect）：

```bash
wget https://github.com/DaehwanKimLab/hisat2/archive/refs/tags/v2.2.3.tar.gz -P ~/software/
tar xzf ~/software/v2.2.3.tar.gz -C ~/software/
make -C ~/software/hisat2-2.2.3 -j4
export PATH=~/software/hisat2-2.2.3:$PATH     # 或加入 ~/.bashrc（用户级，免 root）
```

> 验证安装：`hisat2 --version` 应输出 hisat2 2.2.3（路径一律用户级 `~/software/`，禁教学硬编码路径）。

## 官方实现登记（说明层，不建目录）

### nf-core（Nextflow）

官方 nf-core 模块存在：`modules/nf-core/hisat2/` 含 **3 个子模块** `align / build / extractsplicesites`（2026-09-09 抓取核实），`align` 子模块 conda pin `bioconda::hisat2=2.2.3` + `samtools=1.24`。

```bash
nf-core modules install nf-core hisat2 align      # 在用户项目安装官方子模块
# include: { HISAT2_ALIGN } from './modules/nf-core/hisat2/align/main'
```

> 强提示：本仓库不维护 nf-core 源码目录，仅说明 + Schema；执行前请用 `nf modules install nf-core hisat2 <sub>` 安装到项目自身目录，缺失时用 `native/` 兜底。

### snakemake-wrappers（Snakemake）

官方 snakemake-wrappers 存在：`bio/hisat2/` 含 **2 个 wrapper** `align / index`（2026-09-09 抓取核实；index 对应 hisat2-build），当前 master `align` pin `hisat2=2.2.3` + `samtools=1.24`。

```python
rule hisat2_align:
    input:
        fastq=["reads/{sample}_1.fastq.gz", "reads/{sample}_2.fastq.gz"],
        index="genome.fa"
    output: "mapped/{sample}.sam"
    params: extra="--dta --rna-strandness RF"
    threads: 8
    wrapper: "v9.17.1/bio/hisat2/align"     # tag 以官方 release 为准
```

> 强提示：本目录仅说明层；运行时靠 Snakemake 解析 `wrapper: "v<tag>/bio/hisat2/<sub>"` 句柄，不要把本地示例当 wrapper_path；缺失时用 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造回归 + stub 假二进制 CLI 冒烟（不需要真实 hisat2）
```

## 版本

* hisat2 **2.2.3**（默认锚点；官方 GitHub release v2.2.3，2026-07-31 实测；bioconda / nf-core / snakemake-wrappers 均 2.2.3）
* 上游动态：v2.2.1 长期稳定（2020-2025），2.2.2（2025）/2.2.3（2026）为维护更新；brewsci/bio 公式仍停 **2.2.2**（比官方低一版）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/hisat2 / depot.galaxyproject.org）；本地不再自建容器配方
* hisat2 官方 release 无预编译二进制（源码 make 编译，依赖 zlib + SIMD）

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# hisat2 native Conda 环境配方（与 native/environment.yml 相同）
# 说明：官方镜像（quay.io/biocontainers/hisat2）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def。
name: hisat2-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - hisat2=2.2.3
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/hisat2/overview>（2.2.3 等；linux-64/osx-64/linux-aarch64/osx-arm64）
* **Docker（biocontainers）**：`docker pull quay.io/biocontainers/hisat2:2.2.3--h8471819_1`（同版另有 `2.2.3--h8471819_0`；2.2.1/2.2.2 tag 亦在，以 quay 实时为准）
* **Singularity**：<https://depot.galaxyproject.org/singularity/hisat2%3A2.2.3--h8471819_1>
* **GitHub 官方仓库**：<https://github.com/DaehwanKimLab/hisat2>（releases：v2.2.3 源码 tag 归档）
* **brew**：`brew tap brewsci/bio && brew install hisat2`（brewsci 公式 v2.2.2 源码构建）
* 安装方式（本地）：`mamba create -n hisat2 -c conda-forge -c bioconda hisat2=2.2.3`

## 历史留存

以下为历史教学用法归档，仅作追溯对照；正式能力请走 `main.py` 子命令，安装走本 README「环境安装」（禁 `/opt/biosoft`、`/home/train` 等教学硬编码路径，一律用户级 `~/software/`）：

* HISAT2 由 HISAT（2015，TopHat2 继任者）演进而来（2019 论文）；2.1.0 起索引格式为 `.ht2`，**与 1.x 的 `.ht2` 不同代**，必须用 hisat2-build 重建。
* 旧版本文档（2.1.x/2.2.1）常见「wget 源码 → make → 拷贝到 /opt/biosoft/hisat2-2.2.1/」教学安装；归档时统一用户级前缀。
* 更早的 TopHat2（`tophat2`）流程已被 hisat2 替代，仅作历史对照。
* 早期源码编译时代（2.1.x 及部分 2.2 仓库 commit，如
  `0d244324…/hisat2_extract_splice_sites.py`）`extract_splice_sites.py` /
  `extract_exons.py` / `hisat2_extract_snps_VCF.pl` 等辅助脚本 shebang 为
  **Python 2**，官方教程曾要求自装 Python 2.7（历史步骤：编译
  Python-2.7.11 → `--prefix=~/opt/Python-2.7.11` → PATH 前置后运行辅助脚本；
  原始 commit 页：<https://github.com/DaehwanKimLab/hisat2/blob/0d244324f98de541bce04d45c75e83bc3522f7f4/hisat2_extract_splice_sites.py>）。
  现 2.2.3 release 内脚本能否直接 `python3` 运行以脚本 shebang 为准（本 README
  实战示例即按 python3 可用写法给出）。
* 文档中 `/home/train/...` 教学固定路径为历史残留，不再沿用。
