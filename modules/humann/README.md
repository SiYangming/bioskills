# humann 软件模块

> 汇总说明：本 README 合并各实现用法；安装方式见「环境安装」节，容器与 conda 环境信息记录于此。
> 官方实现（nf-core / snakemake-wrappers）均未收录 humann（2026-09 抓取 404），仅登记 native 实现。

***

## native 实现

# humann / native — 宏基因组功能分析驱动

HUMAnN（HMP Unified Metabolic Analysis Network）的本地自包含实现（`source_type: custom`、`type: native`）。
HUMAnN 是宏基因组 / 宏转录组功能分析流程：输入 reads（或已比对 SAM），依次经
prescreen（MetaPhlAn 物种预筛）→ nucleotide search（bowtie2 / ChocoPhlAn pangenome）→
translated search（diamond / UniRef90）→ 基因家族与代谢通路定量（MinPath），
产出 `*_genefamilies.tsv` / `*_pathabundance.tsv` / `*_pathcoverage.tsv` 丰度表。

## 功能

| 子命令       | 实际命令                 | 作用                                           |
| --------- | -------------------- | -------------------------------------------- |
| `run`     | `humann`             | 主流程：reads/比对 → 基因家族与通路丰度（--threads 自动注入）        |
| `renorm`  | `humann_renorm_table` | 丰度表归一化（cpm / relab）                           |
| `join`    | `humann_join_tables`  | 合并多样本表格（按 --file-name 匹配）                     |
| `regroup` | `humann_regroup_table`| 功能分组重映射（uniref90/uniref50/ec/... 或 --custom 映射）  |
| `databases`| `humann_databases`    | 查询 / 下载 ChocoPhlAn、UniRef、utility 数据库           |

## 用法

```bash
# CLI 直跑
python main.py run --input reads.fastq --output humann_out --threads 8 --bypass-prescreen
python main.py renorm --input humann_out/reads_genefamilies.tsv --output humann_out/reads_genefamilies_cpm.tsv --units cpm
python main.py join --input humann_out/ --output all_genefamilies.tsv --file-name genefamilies.tsv
python main.py regroup --input all_genefamilies.tsv --output all_genefamilies_ec.tsv --groups ec
python main.py databases --available

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（线程仅 `run` 注入 `humann --threads`；
表格/数据库脚本为单线程，参数为契约字段保留）。

## 实战示例：宏基因组 reads 功能分析 → 多样本合并 → 归一化

> 完整功能分析需先下载数据库（ChocoPhlAn / UniRef / MetaPhlAn，可用下方 `humann_databases`），
> 并激活 MetaPhlAn（prescreen 默认开启；跳过预筛可加 `--bypass-prescreen`）。
> 以下为典型批量用法；等价能力由 `native/main.py` 的 `run` / `renorm` / `join` / `regroup` 子命令提供（见上「用法」）。

```bash
# 1) 下载数据库（一次即可；约需数 GB 磁盘，建议放共享目录）
humann_databases --download chocophlan full ~/humann_db/     # 核苷酸库（bowtie2 索引）
humann_databases --download uniref uniref90_diamond ~/humann_db/
humann_databases --download utility full ~/humann_db/        # 可选：utility 映射库

# 2) 逐样本功能分析（输入双端/单端 reads；--input 亦支持目录）
for fq in reads/*.fastq.gz; do
    sample=$(basename "$fq" .fastq.gz)
    humann -i "$fq" -o "humann_out/${sample}" --threads 8
done

# 3) 合并多样本表格（基因家族 / 通路丰度分别合并）
humann_join_tables -i humann_out/ -o all_genefamilies.tsv --file_name genefamilies.tsv
humann_join_tables -i humann_out/ -o all_pathabundance.tsv --file_name pathabundance.tsv

# 4) 归一化（cpm：每百万拷贝；relab：相对丰度）与重分组（可选）
humann_renorm_table -i all_genefamilies.tsv -o all_genefamilies_cpm.tsv --units cpm
humann_regroup_table -i all_genefamilies_cpm.tsv -o all_genefamilies_cpm_ec.tsv --groups ec
```

| 常用参数 | 说明 |
| ------ | ---- |
| `-i/--input` | 输入 reads（fastq/fastq.gz/fasta）或已比对 SAM/BAM；多个文件可用逗号分隔或输入目录 |
| `-o/--output` | 输出目录（主流程；结果文件以输入名为前缀） |
| `--threads` | 线程数（humann 多进程并行，默认 1） |
| `--bypass-prescreen` | 跳过 MetaPhlAn prescreen（需已装 metaphlan + 库才默认执行） |
| `--bypass-nucleotide-search` / `--bypass-translated-search` | 分别跳过 ChocoPhlAn / UniRef 比对层（调试用） |
| `-r/--resume` | 断点续跑（保留已存在输出） |
| `--output-basename` | 输出文件前缀（默认取输入文件名） |
| `--remove-temp-output` | 运行结束后清理中间文件 |

> 数据库下载（`humann_databases --download <database> <build> <location>`）中
> `chocophlan` 对应 `--nucleotide-database`、`uniref` 对应 `--protein-database`；
> 已下载库也可用 `humann_databases --update-config` 设为默认，或运行期显式
> `humann --nucleotide-database <dir> --protein-database <dir>` 指定。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda humann=3.9 → quay.io/biocontainers 官方镜像 → depot.galaxyproject.org 预构建 sif），
直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。
**双版本并存**：bioconda 稳定线仅到 **3.9**（官方镜像路线）；作者 v4 alpha 线
（master 已推进 4.0.0.alpha.2；本库按留存登记 **4.0.0a1**）走 PyPI / 自建 Apptainer.def / 社区镜像，
见下方「作者 v4 alpha 路线（4.0.0a1）」小节与软件级 meta.yaml `software_versions`。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n humann-native -c conda-forge -c bioconda python=3.12 humann=3.9   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate humann-native
humann --version
```

> ⚠️ 必须 pin `python=3.12`：bioconda humann-3.9-py312hdfd78af_0 包内文件硬编码
> `lib/python3.12/site-packages`，conda 环境用其它 python 主版本时模块会装进与解释器
> 不匹配的 site-packages，导致 `humann` 命令 `ModuleNotFoundError`（2026-09 实测）。

> Homebrew：homebrew-core 与 brewsci/bio 均无 humann 公式（2026-09 抓取 formulae.brew.sh 与
> brewsci/homebrew-bio 均 404），不提供 brew 安装块；macOS 用户请走 conda 或 pip（PyPI sdist）。

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境
> `humann`（3.9），无 conda 或 `--version 4.0.0a1` 时自动以 PyPI sdist pip 装到
> `~/software/humann-<ver>` 并写 PATH；版本默认 3.9，与 `software_versions.native` 对齐。
> 用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/humann:3.9--py312hdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/humann:3.9--py312hdfd78af_0 \
    -i /data/reads.fastq -o /data/humann_out --threads 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull humann.sif docker://depot.galaxyproject.org/singularity/humann:3.9--py312hdfd78af_0
apptainer run -B $PWD:/data -H /data humann.sif \
    -i /data/reads.fastq -o /data/humann_out --threads 8
```

### 4. 二进制包安装（官方 release，无 conda / docker 依赖）

HUMAnN 是纯 Python 工具链（官方不发布预编译二进制），官方"release"即 PyPI sdist / GitHub
源码归档，需 pip 安装到 python 环境：

```bash
# 官方 PyPI sdist（pip 自动处理；需本机有 python3；运行期依赖 bowtie2 / diamond / glpk 需另行安装）
python3 -m venv ~/software/humann-3.9/venv
~/software/humann-3.9/venv/bin/pip install humann==3.9
ln -sf ~/software/humann-3.9/venv/bin/humann ~/software/humann-3.9/venv/bin/humann_renorm_table ~/software/humann-3.9/bin/
echo 'export PATH=~/software/humann-3.9/bin:$PATH' >> ~/.bashrc

# 验证安装
humann --version
```

> 提示：数据库（ChocoPhlAn / UniRef）需另用 `humann_databases` 下载（见「实战示例」）。
> 系统依赖 Debian：`apt install bowtie2 diamond-aligner libglpk40`；macOS：
> `brew install bowtie2 diamond-aligner glpk`。conda 路线自动携带全部依赖，最省心。

## 作者 v4 alpha 路线（4.0.0a1）

作者 biobakery/humann master 仍在 v4 alpha 迭代（2026-09 核实：master setup.py
`VERSION = 4.0.0.alpha.2`；PyPI 上另有 4.0.0a1 与 4.0.0a2）。bioconda / quay.io/biocontainers
官方稳定线只有 3.x（最高 3.9），**不提供 4.x alpha 包/镜像**。本库按仓库既有留存
（原 `HUMAnN_4_0_0_a_1.def`）以 **4.0.0a1** 登记作者 v4 alpha 路线，与 native 主路线 3.9 并列声明：

* 容器：`native/Apptainer.def`（debian:bookworm-slim + apt `bowtie2`/`diamond-aligner`/`libglpk40` + pip `humann==4.0.0a1`；自建兜底，供想尝鲜 v4 alpha 的用户），构建后镜像内部 `humann --version` 输出 `humann v4.0.0.alpha.1`；
* 社区镜像备用：`quay.io/bioinfortools/humann:4.0.0a1`；
* 宿主机安装：`bash native/install.sh --version 4.0.0a1 --method pip`（PyPI sdist → venv，见 install.sh 头注）；
* 差异说明：4.0.0a1 为纯 Python sdist（无 install_requires / wheel），运行时需系统 bowtie2 / diamond / glpk（apt/brew 提供）；prescreen 阶段需另 `pip install MetaPhlAn` 并下载数据库；升级 v4 新 alpha 时请以 PyPI / GitHub master 为准同步刷新本文件与 `software_versions.author_v4_alpha`。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（run/renorm/join/regroup/databases）+ 已装 humann 时 --version 冒烟
```

## 版本

* **native 主路线**：humann 3.9（bioconda::humann=3.9；build `py312hdfd78af_0`，2024-06-13 上传，依赖 bowtie2>2.1 / diamond>=0.9.36 / glpk / metaphlan>=4.0）
* **作者 v4 alpha**：4.0.0a1（PyPI sdist 2024-10-28；master 已推进 4.0.0.alpha.2，见上小节）
* 构建路线：官方镜像 / conda 提供 3.9（quay.io/biocontainers / depot.galaxyproject.org；native/ 不维护 3.9 配方）；4.0.0a1 自建 `Apptainer.def`（bioinfortools 社区镜像备用）
* 官方实现：nf-core modules/humann 404、snakemake-wrappers bio/humann 404、brew 两源 404（2026-09 抓取，均未收录）

## 历史留存

仓库既有 `HUMAnN_4_0_0_a_1.def`（作者 v4 alpha 4.0.0a1，ubuntu:24.04 底座）按「唯一文件归位」
改写为 `native/Apptainer.def`：底座改为 debian:bookworm-slim、apt 最小系统依赖 + pip 装 4.0.0a1、
清理四连 + %test 版本断言（见该文件头注）；正式官方路线（3.9）见上方「环境安装」。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# humann native Conda 环境配方（native/environment.yml）
# 离线兜底：可另存为 yml 后 mamba env create -f environment.yml；在线推荐上方 mamba create 直装命令
# 说明：版本与 software_versions.native 对齐（bioconda humann=3.9，自动携带 bowtie2/diamond/glpk/metaphlan）；
#      官方镜像（quay.io/biocontainers/humann:3.9--py312hdfd78af_0）即由 bioconda 该环境构建。
#      python 必须 pin 3.12（humann-3.9-py312 包硬编码 lib/python3.12/site-packages，见「环境安装」）。
name: humann-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.12
  - humann=3.9
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/humann/overview>
* **Docker（官方 3.9）**：`docker pull quay.io/biocontainers/humann:3.9--py312hdfd78af_0`
* **Singularity（官方 3.9）**：<https://depot.galaxyproject.org/singularity/humann%3A3.9--py312hdfd78af_0>
* **社区镜像（作者 4.0.0a1）**：`docker pull quay.io/bioinfortools/humann:4.0.0a1`
* **PyPI（3.9 / 4.0.0a1）**：<https://pypi.org/project/humann/>
* **上游 GitHub**：<https://github.com/biobakery/humann>
* 安装方式（本地）：`mamba create -n humann -c conda-forge -c bioconda python=3.12 humann=3.9`
