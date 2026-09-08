# stringtie 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# stringtie / native — 自包含转录本组装驱动

StringTie 的本地自包含实现（`source_type: custom`、`type: native`；Nanopore long-read 模式）。

## 功能

三个子命令对应 nanoseq 的 STRINGTIE 三段链路：

| 子命令        | 命令                                                                                | 作用                            |
| ---------- | --------------------------------------------------------------------------------- | ----------------------------- |
| `assemble` | `stringtie <bam> --conservative -L -R -G <gtf> -o <out> -l <label> -m <len> -p N` | 样本级转录本重构                      |
| `fix_gtf`  | `awk '$4>$5{交换}'`                                                                 | 修复 GTF 坐标颠倒（纯文本，无需 stringtie） |
| `merge`    | `stringtie --merge -G <gtf> -o <merged> -l MSTRG -m <len> <gtf_list>`             | 多样本非冗余合并                      |

## 用法

```bash
# CLI 直跑
python main.py assemble sample.sorted.bam -G gencode.v49.annotation.gtf -o sample.stringtie.gtf --threads 8
python main.py fix_gtf sample.stringtie.gtf -o sample.stringtie.fixed.gtf
python main.py merge gtf_list.txt -G gencode.v49.annotation.gtf -o stringtie_merged_nonredundant.gtf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：批量组装 → 合并 → 定量 → count 矩阵

StringTie 基于网络流算法，速度比 Cufflinks 快约 10 倍、结果更准确，是当前有参考基因组转录组组装的首选工具。以下为有参转录组（HISAT2 比对后）典型批量用法；等价能力由 `native/main.py` 的 `assemble` / `fix_gtf` / `merge` 子命令提供（见上「用法」）。

### 1. 转录本组装（无参考注释，逐样本 → merge 合并）

```bash
mkdir -p stringtie_assembly
cd stringtie_assembly

# 对每个样品进行转录组组装（-l 样本前缀；-p 线程）
for i in `ls ../hisat2/*.bam`
do
    sample=$(basename $i .bam)
    stringtie $i -l $sample -o ${sample}.gtf -p 8
done

# 将多个 GTF 整合成一个非冗余 GTF
stringtie --merge -o merged.gtf *.gtf
```

### 2. 表达量计算（使用参考注释）

使用参考注释文件进行表达量计算，适用于已有良好注释的物种（`-e` 仅估计注释内转录本，加快速度）。

```bash
mkdir -p stringtie_quant
cd stringtie_quant

for i in `ls ../hisat2/*.bam`
do
    sample=$(basename $i .bam)
    stringtie $i -G ../genome.gtf -e -p 8 -b $sample -o ${sample}.gtf
done
```

### 3. 生成 count 矩阵（prepDE.py3，供 DESeq2 / edgeR 差异分析）

> 提示：bioconda 环境不含 prepDE 脚本，需单独获取。`prepDE.py3`（Python 3 版；历史 Python 2 版为 `prepDE.py`）随官方 GitHub release 包自带，用 `native/install.sh` 的 binary 模式会自动装入 `--prefix/bin`，亦可从 <https://github.com/gpertea/stringtie> 单独下载。
>
> 单独获取历史 Python 2 版 `prepDE.py`（官方软件站直链；若该站不可达，请改用上方 GitHub release 内自带版本）：
>
> ```bash
> wget https://ccb.jhu.edu/software/stringtie/dl/prepDE.py -P ~/software
> chmod 755 ~/software/prepDE.py
> ```

```bash
# 准备 GTF 文件列表（样品名\tGTF 文件路径）
printf 'A\tA.gtf\nB\tB.gtf\nC\tC.gtf\nD\tD.gtf\nE\tE.gtf\nF\tF.gtf\nG\tG.gtf\n' > gtf.list

# 生成 count 矩阵（gene_count_matrix.csv / transcript_count_matrix.csv）
prepDE.py3 -i gtf.list -l 200

# 转制表符分隔并去掉行首 'gene|' 前缀
perl -p -e 's/,/\t/g; s/^.*\|//' gene_count_matrix.csv | sort > gene_count_matrix.tab
```

### 4. 参数说明

| 参数        | 说明                            |
| --------- | ----------------------------- |
| `-G`      | 参考注释 GTF                      |
| `-e`      | 仅估计参考注释中的转录本表达量（加快速度）         |
| `-b`      | 输出 Ballgown 格式的表达量数据          |
| `-l`      | 转录本前缀                         |
| `-p`      | CPU 线程数                       |
| `--merge` | 合并模式，整合多个样品的 GTF 文件           |
| `--rf`    | 链特异性文库 fr-firststrand（dUTP 法） |
| `--fr`    | 链特异性文库 fr-secondstrand        |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n stringtie-native -c conda-forge -c bioconda stringtie=3.0.3   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate stringtie-native
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install stringtie
stringtie --version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `stringtie`，无 conda 时自动下载官方 GitHub release 二进制到 `~/software/stringtie-<ver>` 并写 PATH；版本默认 3.0.3，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/stringtie:3.0.3--h29c0135_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/stringtie:3.0.3--h29c0135_0 assemble \
    sample.sorted.bam -G gencode.v49.annotation.gtf -o sample.stringtie.gtf
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull stringtie.sif docker://depot.galaxyproject.org/singularity/stringtie:3.0.3--h29c0135_0
apptainer run -B $PWD:/data -H /data stringtie.sif assemble \
    /data/sample.sorted.bam -G /data/gencode.v49.annotation.gtf -o /data/sample.stringtie.gtf
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

* **官网**：<https://ccb.jhu.edu/software/stringtie/>

* **GitHub**：<https://github.com/gpertea/stringtie>

官方二进制已迁移至 GitHub release 分发（旧的 `ccb.jhu.edu/.../dl/` 下载页已失效，此处更新为当前版本 3.0.3，与下方 `software_versions` 对齐）：

```bash
# 下载 StringTie
wget https://github.com/gpertea/stringtie/releases/download/v3.0.3/stringtie-3.0.3.Linux_x86_64.tar.gz -P ~/software/

# 解压安装（解压到用户目录后加 PATH，无需 root）
tar zxf ~/software/stringtie-3.0.3.Linux_x86_64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/stringtie-3.0.3.Linux_x86_64/' >> ~/.bashrc
source ~/.bashrc

# 验证安装
stringtie --version
```

> 💡 **说明**：release 包内自带 `prepDE.py3`（用于生成 count 矩阵，见「实战示例 §3」），解压目录内即可使用，无需单独下载；conda 安装的 stringtie 不含该脚本。

## 测试

```bash
bash test/run_test.sh   # fix_gtf 为真实回归；assemble/merge 退化为 argv 构造验证
```

## 版本

* stringtie 3.0.3（bioconda::stringtie=3.0.3）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/stringtie / depot.galaxyproject.org；本地不再自建容器）

* 与 nf-core 子模块 stringtie/stringtie + stringtie/merge 的 bioconda pin 一致

## 历史留存

多步组合脚本（逐样本 assemble + 坐标修复 + 跨样本 merge）的流程版见 `workflow/nanoseq/native/03_run_stringtie.sh`（Stage 03 · StringTie；硬编码项目路径，仅供追溯对照 / 一键运行）；正式能力请走 `main.py` 的 assemble / fix\_gtf / merge 原子子命令。

***

## snakemake 实现

# stringtie / snakemake / local — 自维护 Snakemake 规则（td2 式单规则拆分）

官方 `snakemake-wrappers` 无 `bio/stringtie`（抓取 404），因此本目录提供自维护规则，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。
规则按子命令拆为**每 rule 一个 config 驱动 .smk**（参照 td2/bbmap 规范；conda 环境与
wrapper 平铺于 `snakemake/` 根，规则内 `conda:` / `script:` 一律用同目录相对名）：

## 规则文件

| 规则文件                     | 规则                   | 命令                                                                                | 执行指令                                             |
| ------------------------ | -------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------ |
| `stringtie_assemble.smk` | `stringtie_assemble` | `stringtie <bam> --conservative -L -R [-G <gtf>] -o <out> -l <label> -m 200 -p N` | `script:` 同目录 wrapper（docker/native/conda 三模式分派） |
| `stringtie_fix_gtf.smk`  | `stringtie_fix_gtf`  | `awk -F'\t' -v OFS='\t' -f fix_gtf.awk <gtf>`（坐标修复 $4<=$5，纯文本）                    | `script:` 同目录 wrapper `stringtie_fix_gtf.py`     |
| `stringtie_merge.smk`    | `stringtie_merge`    | `stringtie --merge [-G <gtf>] -o <merged> -l MSTRG -m 200 <gtf_list>`             | `script:` 同目录 wrapper（docker/native/conda 三模式分派） |

配套文件（同目录平铺，无 `envs/` / `scripts/` 幽灵引用）：

* `stringtie.yaml` —— assemble/merge 共用的 conda 环境（bioconda `stringtie==3.0.3`）

* `stringtie_assemble.py` / `stringtie_merge.py` —— assemble/merge 的 script wrapper（两级注入共享
  `modules/docker_wrapper.py`，docker/native/conda 三模式分派）

* `stringtie_fix_gtf.py` + `fix_gtf.awk` —— fix\_gtf 的 script wrapper 与其 awk helper：
  wrapper 以 `Path(__file__).parent` 定位**同目录** `fix_gtf.awk`（helper 归属本目录，同目录相对定位；
  该规则纯文本处理、不挂 conda，awk 走系统 PATH）

去除 nohup/PID/LOCK 后台运行封装、绝对路径与 GNU parallel 依赖；规则 **config 驱动**
（`config.setdefault` 默认值 + `--config` 覆盖，头注含完整契约与独立运行示例），不依赖
workflow 的 SAMPLES / {sample} 目录层级。merge 的输入 GTF 列表文件由流程层对逐样本
`stringtie_fix_gtf` 产物汇总生成（`ls` / `find` 写列表，每行一个 GTF）。

## 用法

独立运行（每个 .smk 头注均有 config 契约）：

```bash
# assemble：BAM -> 样本级 GTF
snakemake -s modules/stringtie/snakemake/stringtie_assemble.smk \
    --config stringtie_bam=sample.sorted.bam \
             stringtie_gtf_annotation=gencode.v49.annotation.gtf \
    --cores 8 --use-conda

# fix_gtf：坐标修复（无需 conda / 不需要 stringtie 二进制）
snakemake -s modules/stringtie/snakemake/stringtie_fix_gtf.smk \
    --config stringtie_gtf=sample.stringtie.gtf \
             stringtie_fixed_gtf=sample.stringtie.fixed.gtf

# merge：多样本非冗余合并（gtf_list 每行一个 GTF，由流程层生成）
snakemake -s modules/stringtie/snakemake/stringtie_merge.smk \
    --config stringtie_gtf_list=gtf_list.txt \
             stringtie_gtf_annotation=gencode.v49.annotation.gtf \
    --cores 4 --use-conda
```

流程内（Snakefile 中 include 各单规则并串起三段链路）：

```python
include: "modules/stringtie/snakemake/stringtie_assemble.smk"
include: "modules/stringtie/snakemake/stringtie_fix_gtf.smk"
include: "modules/stringtie/snakemake/stringtie_merge.smk"

rule all:
    input: config["stringtie_merged_gtf"]   # merge 输入列表由流程层规则生成
```

## 与其它实现的关系

* 官方 snakemake-wrappers 无 `bio/stringtie`（2026-09 抓取 404，登记于软件级 meta.yaml `software_versions` / implementations）；若未来官方 wrapper 出现，可改走 `wrapper:` 句柄，本目录规则作 `../local` 兜底

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走本模块 `native/`（见上「native 实现」节）

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# stringtie native Conda 环境配方
# 离线兜底：可另存为 stringtie-native.yml 后 mamba env create -f stringtie-native.yml；在线推荐上方 mamba create 直装命令
# 说明：stringtie 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      官方镜像（quay.io/biocontainers/stringtie）即由 bioconda 本环境构建；本地不再自建 Dockerfile/Apptainer.def（见上「环境安装」）。
name: stringtie-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - stringtie=3.0.3
  - pyyaml>=6.0
  - pip
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/stringtie/overview>

* **Docker**：`docker pull quay.io/biocontainers/stringtie:3.0.3--h29c0135_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/stringtie%3A3.0.3--h29c0135_0>

* 安装方式（本地）：`mamba create -n stringtie -c conda-forge -c bioconda stringtie=3.0.3`

