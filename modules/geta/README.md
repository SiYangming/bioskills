# geta 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方「环境安装」，容器与 conda 信息记录于文末。
> 本模块仅登记 native 实现（官方 nf-core / snakemake-wrappers 均无 geta，见文末「官方实现登记」）。

***

## native 实现

# geta / native — 自包含一站式自动基因预测驱动

GETA（chenlianfu）的本地自包含实现（`source_type: custom`、`type: native`；Perl 驱动）。

## 功能

GETA 是一个自动化基因预测流程，整合了重复序列注释、基因预测、结果整合等多个步骤。

三个子命令覆盖 GETA 主链路：

| 子命令           | 命令                                                                                                                        | 作用                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `geta`        | `geta.pl --RM_species <s> --genome <genome> [-1 <r1>] [-2 <r2>] [--protein <faa>] [--use_existed_augustus_species <n>] [--RM_lib <lib>] --cpu N [--pfam_db <hmm>] [--gene_prefix <p>]` | 一站式自动基因预测（重复注释 + AUGUSTUS/同源 + 整合） |
| `best_models` | `bestGeneModels.pl <out.gff3>`                                                                                            | 去除可变剪接，保留最优基因模型                |
| `gff3_to_gtf` | `gff3ToGtf.pl <genome.fasta> <bestGeneModels.gff3>`                                                                       | GFF3 → GTF                     |

> ⚠️ 版本核实：`bestGeneModels.pl` 未在官方仓库 `bin/` 下命中（master / v2.7.1 / 2.4.5 均 404，2026-09-11 核实），本驱动按 PATH 解析（随 GETA/教学环境安装提供）；`geta.pl` / `gff3ToGtf.pl` 均已命中。

## 用法

```bash
# CLI 直跑
python main.py geta --RM_species fungi --genome genome.fasta -1 reads.1.fastq -2 reads.2.fastq \
    --protein homolog.fasta --use_existed_augustus_species malassezia_sympodialis \
    --RM_lib consensi.fa --pfam_db Pfam-AB.hmm --gene_prefix MS01Gene --threads 8
python main.py best_models out.gff3 -o bestGeneModels.gff3
python main.py gff3_to_gtf genome.fasta bestGeneModels.gff3 -o bestGeneModels.gtf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`geta` 注入 `--cpu N`）。

## 实战示例：一站式自动基因预测（GETA）

GETA 整合重复序列注释、基因预测、结果整合等多个步骤，可自动完成从基因组到基因模型的全流程。以下为典型用法；预测 / 去可变剪接 / GFF3→GTF 等价能力由 `native/main.py` 的 `geta` / `best_models` / `gff3_to_gtf` 子命令提供（见上「用法」）。

```bash
mkdir -p GETA && cd GETA
ln -s ../Malassezia_sympodialis.genome_V01.fasta genome.fasta

# 1) 准备同源蛋白 / 重复序列库 / RNA-seq reads
gzip -dc ../GCF_000328475.2_Umaydis521_2.0_protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta
ln -s ../RepeatModeler_database.consensi.fa consensi.fa
cat ../*.1.fastq > reads.1.fastq
cat ../*.2.fastq > reads.2.fastq

# 2) 使用已训练好的 AUGUSTUS 物种参数运行 GETA
geta.pl --RM_species fungi --genome genome.fasta -1 reads.1.fastq -2 reads.2.fastq \
    --protein homolog.fasta --use_existed_augustus_species malassezia_sympodialis \
    --RM_lib consensi.fa --cpu 8 --pfam_db Pfam-AB.hmm --gene_prefix MS01Gene &> geta.log

# 3) 处理结果：去可变剪接保留最优模型，并转换 GTF
bestGeneModels.pl out.gff3 > bestGeneModels.gff3 2> geneModelsStatistic
gff3ToGtf.pl genome.fasta bestGeneModels.gff3 > bestGeneModels.gtf
```

| 参数                                        | 说明                        |
| ----------------------------------------- | ------------------------- |
| `--RM_species fungi`                      | RepeatMasker 物种类型         |
| `--genome genome.fasta`                   | 基因组序列文件                   |
| `-1 reads.1.fastq` / `-2 reads.2.fastq`    | RNA-seq 正向 / 反向 reads（可选）  |
| `--protein homolog.fasta`                 | 同源蛋白序列文件                  |
| `--use_existed_augustus_species <name>`   | 使用已训练好的 AUGUSTUS 物种参数      |
| `--RM_lib consensi.fa`                    | 重复序列数据库                   |
| `--cpu 8`                                 | 并行线程数                     |
| `--pfam_db Pfam-AB.hmm`                   | Pfam 数据库路径                |
| `--gene_prefix MS01Gene`                  | 基因 ID 前缀                  |

> 注意事项：GETA 是一站式工具，自动完成多步骤；需提前准备基因组、同源蛋白、重复序列库、RNA-seq 等输入；推荐使用已训练好的 AUGUSTUS 物种参数以提高准确性。

## 环境安装（自建兜底：GETA 无官方镜像 / 无 conda 包，apt 最小化 + 官方 tarball）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）2026-09-11 核实**全无** geta 包与镜像（bioconda API 404；brew / nf-core / snakemake-wrappers 亦 404），故本模块**自建** apt 最小化配方（`native/Dockerfile` + `native/Apptainer.def`）与宿主机安装脚本（`native/install.sh`）。官方仅以 GitHub tag tarball 分发（`geta-<ver>/bin/*.pl`，解压即用，非编译）。

### 1. Conda / brew（包管理器安装，备选）

```bash
# ⚠️ 官方无 bioconda geta 包（2026-09-11 核实 404）；conda 只能提供 perl 运行时，
#    geta 脚本仍需从官方 tarball 获取（见 native/install.sh --method conda 的实现）。
# brew（homebrew-core / brewsci-bio）亦无 geta 公式（2026-09-11 核实 404）→ 不登记。
```

> 一键安装直接运行 `native/install.sh`（有 conda/mamba 时用其提供 perl 并把官方 tarball 的 `*.pl` 部署到环境 `bin/`；无 conda 时解压官方 tarball 到用户前缀 `~/software/geta-<ver>` 并写 PATH。版本默认 2.7.1，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（自建镜像）

```bash
# 构建（context 必须是 modules/ 层，以携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/geta:2.7.1 -f modules/geta/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/geta:2.7.1 --help
# 驱动 main.py
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/geta:2.7.1 \
    /opt/skill/main.py gff3_to_gtf /data/genome.fasta /data/bestGeneModels.gff3 -o /data/bestGeneModels.gtf
```

### 3. Apptainer / Singularity（自建镜像）

depot.galaxyproject.org **无 geta 预构建 sif**，需用本模块自带的 `Apptainer.def` 本地构建：

```bash
cd modules && apptainer build geta-2.7.1.sif geta/native/Apptainer.def
apptainer run -B $PWD:/data -H /data geta-2.7.1.sif --help
# 驱动 main.py：apptainer exec geta-2.7.1.sif python3 /opt/skill/main.py \
#     gff3_to_gtf /data/genome.fasta /data/bestGeneModels.gff3 -o /data/bestGeneModels.gtf
```

### 4. 官方 tarball 解压（无 conda / docker 依赖）

```bash
# 官方 tag tarball（解压即用，非编译）
curl -fSL -o geta-2.7.1.tar.gz https://github.com/chenlianfu/geta/archive/refs/tags/v2.7.1.tar.gz
tar zxf geta-2.7.1.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/geta-2.7.1/bin/' >> ~/.bashrc
source ~/.bashrc
geta.pl --help
```

> 说明：官方 tag tarball 的 sha256 已内嵌于 `native/install.sh` 与 `native/Dockerfile`（2026-09-11 实测下载 17098074 B，`a80d8d44…b8786`）；教学文档另用 tag 2.4.5（<https://github.com/chenlianfu/geta/archive/2.4.5.tar.gz>）。geta.pl 为 Perl 驱动，完整预测还需 AUGUSTUS/RepeatMasker/同源比对等外部工具（本模块容器仅含 geta 脚本 + perl/python3 运行时）。

## 官方实现登记（nf-core / snakemake-wrappers）

* **nf-core**：`modules/nf-core/geta` 不存在（2026-09-11 核实 404）→ 未建立 nextflow 说明层，Nextflow 场景请以本模块 `native/` 为兜底。
* **snakemake-wrappers**：`bio/geta` 不存在（2026-09-11 核实 404）→ 未建立 snakemake 说明层，Snakemake 场景请以本模块 `native/` 为兜底。

## 测试

```bash
bash test/run_test.sh   # geta/best_models/gff3_to_gtf 退化为 argv 构造验证（不依赖已安装 GETA）
```

## 版本

* GETA 2.7.1（官方 GitHub tag tarball；教学文档另用 2.4.5）
* 构建路线：官方渠道全无 → **自建**（debian:bookworm-slim + apt 最小化 + 官方 tarball 解包；本地 Dockerfile/Apptainer.def）
* `geta.pl` / `gff3ToGtf.pl` 官方仓库 bin/ 命中；`bestGeneModels.pl` 未命中（404），按 PATH 解析
* 完整预测依赖 AUGUSTUS/RepeatMasker/同源比对等外部工具

## 容器与 Conda 链接

* **官方仓库**：<https://github.com/chenlianfu/geta>
* **官方 tarball**：<https://github.com/chenlianfu/geta/archive/refs/tags/v2.7.1.tar.gz>
* **Docker（自建）**：`docker build -t bioskills/geta:2.7.1 -f modules/geta/native/Dockerfile modules/`
* **Apptainer（自建）**：`cd modules && apptainer build geta-2.7.1.sif geta/native/Apptainer.def`
* **Bioconda / quay / depot**：无（2026-09-11 核实 404，故不登记镜像直链）
* 安装方式（本地）：`bash native/install.sh`（详见「环境安装」）
