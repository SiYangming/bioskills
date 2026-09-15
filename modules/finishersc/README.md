# finishersc 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方「环境安装」，容器与 conda
> 环境信息见文末「容器与 Conda 链接」。
>
> FinisherSC（Finishing Tool，Lam K.K. et al., Bioinformatics 2015, 31(19):3207-3209）是用 PacBio
> 长读数据对 de novo 组装做 **repeat-aware 迭代升级**的工具：逐步填补 contig 间 gap 并修正组装错误，
> 依次产出 `noEmbed.fasta` / `improved.fasta` / `improved2.fasta` / `improved3.fasta`（关键输出为
> `improved3.fasta`）。官网 <https://kakitone.github.io/finishingTool/>，源码
> <https://github.com/kakitone/finishingTool>。脚本为 **Python 2**，依赖 **MUMmer**。
> 本模块仅实现 `native/`（`finish` 子命令）；官方登记：**nf-core `modules/nf-core/finishersc` 404、
> snakemake-wrappers `bio/finishersc` 404**（2026-09 核实）→ 不建 nextflow/、snakemake/ 目录。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/finishersc/` **不存在**（2026-09 抓取返回 404）。
* **snakemake-wrappers**：`bio/finishersc` **不存在**（2026-09 抓取返回 404）。

***

## native 实现

# finishersc / native — 长读组装升级驱动（FinisherSC v2.1）

FinisherSC 的本地自包含实现（`source_type: custom`、`type: native`）。上游为 Python 2 脚本集合，
官方 CLI 形态（`python finisherSC.py <folderName> <mummerLink> [选项]`）：

```
python finisherSC.py -par 8 -l True -o contigs.fasta_improved3.fasta ./ /path/to/mummer/bin/
```

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `finish` | `python finisherSC.py -par N [-l True] [-f True] [-p <pickup>] [-o <mapcontigs>] <folder> <mummer>` | 以 PacBio 长读对组装逐轮补 gap/纠错，产出 `improved3.fasta`；`--threads` 自动注入 `-par` |

> * `-l True`：大 contig 集模式（拆分比对）；`-f True`：快速模式（速度更快、质量略有折中）。
> * `-p <pickup>`：断点续跑起点（`noEmbed.fasta`/`improved.fasta`/`improved2.fasta`）。
> * `-o <mapcontigs>`：教学文档注释写作「输出文件名」，**上游 argparse 实为 mapcontigs**
>   （将 `improved3.fasta` 映射回旧 contig，输出 `mappingResults.txt`）；关键输出始终是
>   `<folder>/improved3.fasta`。
> * `<mummerLink>` 是 **MUMmer 可执行文件所在目录**（含 `nucmer`/`show-coords` 等）。

## 用法

```bash
# CLI 直跑（教学文档形态：-par 8 -l True -o contigs.fasta_improved3.fasta ./ <mummer bin>）
python main.py finish ./ /opt/mummer-4.0.0beta2/bin/ --large \
    --mapcontigs contigs.fasta_improved3.fasta --threads 8
# 快速模式 + 断点续跑
python main.py finish ./ /opt/mummer-4.0.0beta2/bin/ --fast --pickup improved.fasta --threads 16

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--threads` 优先级：用户显式 >
`optimization.per_subcommand_threads.finish` > `default_cpus`。

## 实战示例：PacBio 组装的 FinisherSC 迭代升级

> 典型用法如下；**等价能力由 `native/main.py` 的
> `finish` 子命令提供**（draft 组装由 Canu/quickmerge 完成，见各自模块）。

```bash
mkdir -p FinisherSC && cd FinisherSC

# 1) 建立数据符号链接：destinedFolder 必须含 contigs.fasta 与 raw_reads.fasta
ln -s ../quickmerge/quickmerge.fasta contigs.fasta
ln -s ../Canu/subreads.fasta          raw_reads.fasta

# 2) 运行 FinisherSC（-par 8 八线程；-l True 保留/拆分大组装；-o 指定映射；./ 工作目录；
#    末尾为 MUMmer 可执行文件目录）
python /path/to/finishingTool/finisherSC.py -par 8 -l True \
    -o contigs.fasta_improved3.fasta ./ /opt/biosoft/mummer-4.0.0beta2/bin/
#   等价驱动调用（等价能力由 native/main.py 的 finish 子命令提供）：
#   python main.py finish ./ /opt/mummer-4.0.0beta2/bin/ --large \
#       --mapcontigs contigs.fasta_improved3.fasta --threads 8

# 3) 格式化结果（关键输出 improved3.fasta；坐标/序列清理按需）
ls -l improved3.fasta
```

### 参数说明

| 参数（main.py / finisherSC.py） | 说明 |
| --- | --- |
| `<folder>`（位置参数） | 工作目录（destinedFolder），须含 `contigs.fasta` 与 `raw_reads.fasta` |
| `<mummer>`（位置参数） | MUMmer 可执行文件目录（`nucmer`/`show-coords` 等） |
| `-par` / `--threads` | 并行线程数（驱动自动注入；默认 8） |
| `-l` / `--large` | 大 contig 集模式（对应 `-l True`） |
| `-f` / `--fast` | 快速模式（对应 `-f True`） |
| `-p` / `--pickup` | 断点续跑起点（`noEmbed.fasta`\|`improved.fasta`\|`improved2.fasta`） |
| `-o` / `--mapcontigs` | 将新 contig 映射回旧 contig（结果见 `mappingResults.txt`） |

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道 2026-09 逐渠道核实**均无 finishersc conda 包/官方镜像**（bioconda API 404；
quay.io/biocontainers 401=无仓库；depot.galaxyproject.org `singularity/finishersc:latest` 404；
nf-core / snakemake-wrappers / brew 亦 404）→ 无官方镜像可直拉，`native/` 提供**自建配方**
`Dockerfile` + `Apptainer.def`（debian:bullseye-slim + apt python2.7/mummer + 官方源码，**不引入
miniconda**；底座用 bullseye 因 finisherSC.py 为 Python 2 语法）。宿主机直跑 `main.py` 时按下面
1/4 安装 finisherSC.py 与运行依赖。

### 1. Conda / brew（包管理器安装）

FinisherSC **不在 bioconda，也不在 conda-forge**（2026-09 核实：`api.anaconda.org/package/bioconda/
finishersc` 404）；homebrew 两源均无（`finishersc.json` 404、brewsci/bio `Formula/finishersc.rb`
404）→ 不提供 conda 工具包 / brew 块。conda 只能装**运行依赖**（Python 2 + MUMmer）：

```bash
# 依赖：Python 2.7（finisherSC.py 为 Python 2 语法）+ MUMmer（nucmer/show-coords）
mamba create -n finishersc-deps -c conda-forge -c bioconda python=2.7 mummer
conda activate finishersc-deps
# finisherSC.py 本体：无 conda 包 → 见下方 §4 源码部署（或自建容器）
```

> 一键安装直接 `bash native/install.sh`（源码部署 `finisherSC.py` 到 `~/software/finishingTool-2.1`
> 并写 PATH；自动检测 Python 2 与 MUMmer；`bash native/install.sh --help` 看参数）。

### 2. Docker（自建镜像；无官方镜像可拉）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；context 必须是 modules/ 层以携带驱动代码）
docker build -t bioskills/finishersc:2.1 -f modules/finishersc/native/Dockerfile modules/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
#   容器内 MUMmer 在 /usr/bin（作第 2 位置参数传 /usr/bin）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/finishersc:2.1 \
    -par 8 -l True -o contigs.fasta_improved3.fasta /data /usr/bin
# 驱动 main.py：
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/finishersc:2.1 \
    /opt/skill/main.py finish /data /usr/bin --large --threads 8
```

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 finishersc），本地构建：

```bash
# 构建（%files 源路径相对 apptainer build 时的 cwd=modules/）
cd modules && apptainer build finishersc-2.1.sif finishersc/native/Apptainer.def
apptainer run -B $PWD:/data -H /data finishersc-2.1.sif \
    -par 8 -l True -o contigs.fasta_improved3.fasta /data /usr/bin
```

### 4. 二进制包安装（官方源码部署；官方无预编译二进制）

官方**仅发布 Python 源码**（GitHub，教学文档 zip 名 `kakitone-finishingTool-v2.1-2-ga1f2608.zip`），
无预编译二进制 release：

```bash
# 依赖：Python 2.7 + MUMmer（见 §1）
# 部署：一键走 native/install.sh（下载 codeload zip -> ~/software/finishingTool-2.1 -> 写 PATH）
bash native/install.sh
export FINISHERSC_HOME=$HOME/software/finishingTool-2.1   # main.py 依此定位 finisherSC.py
# 手动等价：
#   wget https://codeload.github.com/kakitone/finishingTool/legacy.zip/master -O finishingTool.zip
#   unzip finishingTool.zip -d ~/software/ && mv ~/software/kakitone-finishingTool-* ~/software/finishingTool-2.1
```

> ⚠️ 上游 finisherSC.py **无 `--version`**（脚本内亦无版本常量）：版本以登记 v2.1 + 源码就位为准
> （`install.sh`/容器 `%test` 做结构化断言）；codeload zip 的 sha256 动态变化，**未核实**，不编造。

## 测试

```bash
bash modules/finishersc/native/test/run_test.sh   # 自省 + argv 构造断言恒跑；finisherSC.py 已部署时做存在性冒烟
```

## 容器与 Conda 链接

* **官网**：<https://kakitone.github.io/finishingTool/>
* **官方源码**：<https://github.com/kakitone/finishingTool>
* **Bioconda**：无 finishersc 包（<https://anaconda.org/bioconda/finishersc> 404，2026-09 核实）
* **quay.io/biocontainers / depot.galaxyproject.org**：均无（quay 401=无仓库、depot `finishersc:latest` 404，2026-09）
* **Homebrew**：两源均无（2026-09 核实）→ 无 brew 块
* **自建容器**：`modules/finishersc/native/Dockerfile`
  （`docker build -t bioskills/finishersc:2.1 -f modules/finishersc/native/Dockerfile modules/`）、
  `modules/finishersc/native/Apptainer.def`
  （`cd modules && apptainer build finishersc-2.1.sif finishersc/native/Apptainer.def`）
* **MUMmer（运行依赖）**：<https://github.com/mummer4/mummer>（或 apt/conda `mummer`）

## 版本

* FinisherSC **v2.1**（Finishing Tool；教学文档 zip 名 `kakitone-finishingTool-v2.1-2-ga1f2608.zip`）
* 运行依赖：**Python 2.7**（finisherSC.py 为 Python 2 语法）+ **MUMmer**（nucmer/show-coords 等）
* 构建路线：官方渠道全无 → native 自建配方（debian:bullseye-slim + apt python2.7/mummer + 官方源码）
* 官方无 Nextflow / Snakemake wrapper（`modules/nf-core/finishersc`、`bio/finishersc` 均 404）
