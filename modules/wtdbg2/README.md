# wtdbg2 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 wtdbg2 子模块（2026-09 抓取 404），故本模块只提供 `native/` 实现。

***

## native 实现

# wtdbg2 / native — 自包含长读组装驱动

wtdbg2（Wtdbg2）的本地自包含实现（`source_type: custom`、`type: native`；模糊德布鲁因图长读组装）。

## 功能

三个子命令覆盖 wtdbg2 的建图→一致性→打磨链路（自动按子命令解析 `wtdbg2` 或 `wtpoa-cns`）：

| 子命令        | 命令（核心）                                                                               | 作用                        |
| ---------- | ----------------------------------------------------------------------------------- | ------------------------- |
| `assemble` | `wtdbg2 -i <reads> -o <prefix> -t N -p 21 -S 4 -s 0.05 -g <size> -L 2000 -l 1000`    | 建图（产出 `<prefix>.ctg.lay.gz`） |
| `cns`      | `wtpoa-cns -t N -j 1000 -i <prefix>.ctg.lay.gz -fo <out.fa>`                          | 取一致性序列                     |
| `polish`   | `wtpoa-cns -t N [-x sam-sr] -d <draft.fa> -i <aln\|-> -fo <out.fa>`                   | 用比对结果打磨（长读自身/短读）           |

## 用法

```bash
# CLI 直跑（仿文档 Malassezia 示例）
python main.py assemble subreads.fasta -o dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
python main.py cns dbg.ctg.lay.gz -fo dbg.raw.fa -t 8 -j 1000

# 打磨：长读自身打磨（aligned BAM 经 stdin 管道）
python main.py polish dbg.raw.fa -i dbg.bam -fo dbg.cns.fa -t 8
# 打磨：短读打磨（-x sam-sr，- 表示读 stdin）
python main.py polish dbg.cns.fa -i - -fo dbg.srp.fa -t 8 --preset sam-sr

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例

wtdbg2 基于模糊德布鲁因图，面向长读数据、速度快且内存效率高。以下为文档给出的完整四步用法；等价能力由 `native/main.py` 的 `assemble` / `cns` / `polish` 子命令提供。

```bash
mkdir -p 04.genome_assembling/wtdbg2/Malassezia_sympodialis
cd 04.genome_assembling/wtdbg2/Malassezia_sympodialis
ln -s /path/to/Canu/Malassezia_sympodialis/subreads.fasta ./

# 第一步：构建组装图
# -i 输入序列 -o 输出前缀 -t 线程 -p k-mer -S 采样率 -s 错误率 -g 基因组大小 -L 最小 read -l 最小重叠
wtdbg2 -i subreads.fasta -o dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000

# 第二步：得到一致性序列
wtpoa-cns -t 8 -j 1000 -i dbg.ctg.lay.gz -fo dbg.raw.fa

# 第三步：利用三代 reads 打磨修正（minimap2 + samtools 比对回贴）
minimap2 -t 8 -a -x map-pb -r 500 dbg.raw.fa subreads.fasta | samtools sort -@ 4 -O BAM -o dbg.bam
samtools view -F0x900 dbg.bam | wtpoa-cns -t 8 -d dbg.raw.fa -i - -fo dbg.cns.fa

# 第四步：利用二代 reads 打磨修正（bwa mem 比对 + -x sam-sr 短读打磨）
bwa mem -t 8 dbg.cns.fa illumina.1.fastq illumina.2.fastq | samtools sort -O SAM \
    | wtpoa-cns -t 8 -x sam-sr -d dbg.cns.fa -i - -fo dbg.srp.fa
```

> 桥接句：第一、二步的 `wtdbg2 ...` / `wtpoa-cns ...` 等价能力由 `native/main.py` 的 `assemble` 与 `cns` 子命令提供；第三、四步的打磨由 `polish` 子命令提供（比对回贴的 minimap2/samtools/bwa 步骤请走各自软件模块或 shell 管道）。

### 依赖说明

| 步骤        | 依赖                              |
| --------- | ------------------------------- |
| `assemble` / `cns` | 仅 wtdbg2 自身（`wtdbg2` + `wtpoa-cns`） |
| `polish`  | 需 `minimap2`（长读）/ `bwa`（短读）+ `samtools` 产出比对结果 |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），且官方 release v2.5 提供预编译二进制包；直接取官方预编译包或拉官方镜像运行，main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
# ⚠️ bioconda 包名为 wtdbg（不是 wtdbg2）
mamba create -n wtdbg2-native -c conda-forge -c bioconda wtdbg=2.5
conda activate wtdbg2-native
wtdbg2 -V   # 断言（wtdbg2 用 -V 打印版本）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先 tap）
brew tap brewsci/bio
brew install wtdbg2
wtdbg2 -V   # 断言
```

> 📌 brew 公式为 `brewsci/bio/wtdbg2`（v2.5，仅 x86_64 Linux bottle）；homebrew-core 无 wtdbg2（2026-09 核实 404）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/wtdbg:2.5--h577a1d6_6
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/wtdbg:2.5--h577a1d6_6 \
    wtdbg2 -i subreads.fasta -o dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull wtdbg.sif docker://depot.galaxyproject.org/singularity/wtdbg:2.5--h577a1d6_6
apptainer run -B $PWD:/data -H /data wtdbg.sif \
    wtdbg2 -i /data/subreads.fasta -o /data/dbg -t 8 -p 21 -S 4 -s 0.05 -g 8m -L 2000 -l 1000
```

### 4. 官方预编译二进制包（首选）

官方 release **v2.5** 提供 Linux x86_64 预编译包（2026-09 核实存在；预编译包内含 `wtdbg2`、`wtpoa-cns`、`wtdbg-cns`、`kbm2`、`pgzf`、`wtdbg2.pl`）：

```bash
# 下载
wget https://github.com/ruanjue/wtdbg2/releases/download/v2.5/wtdbg-2.5_x64_linux.tgz -P ~/software/

# 解压到用户目录（无需 root；禁 /opt/biosoft）
tar zxf ~/software/wtdbg-2.5_x64_linux.tgz -C ~/software/
echo 'export PATH=$PATH:~/software/wtdbg-2.5_x64_linux/' >> ~/.bashrc
source ~/.bashrc

# 验证
wtdbg2 -V
```

> 一键安装可走 `bash native/install.sh --method binary`（内嵌官方 v2.5 sha256：`a3ed9ef2587fba7aaf9cc19108288cddd43938dc16665dafead9fc66d200b780`）。
> ⚠️ 预编译包仅覆盖 **linux-x86_64**；macOS 请走 conda 或源码编译。

### 5. 官方源码编译（并列保留）

```bash
git clone https://github.com/ruanjue/wtdbg2.git
cd wtdbg2
make            # 生成 wtdbg2 / wtpoa-cns 等
# 可选：安装到用户前缀
make install BIN=~/software/wtdbg-2.5/bin
```

> 💡 说明：文档「wtdbg2 暂无官方 conda 包」不准确——bioconda **有**该软件包，但包名为 `wtdbg`（`wtdbg2` 查询 404）。

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（建图需真实长读数据）
```

## 版本

* wtdbg2 2.5（官方 release v2.5 / bioconda `wtdbg=2.5` / 容器 tag `wtdbg:2.5--h577a1d6_6`）
* 构建路线：官方镜像/conda/官方预编译包提供（quay.io/biocontainers/wtdbg / depot.galaxyproject.org；本地不再自建容器）
* 打磨阶段依赖 minimap2 + samtools（独立安装）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/wtdbg/overview>
* **Docker**：`docker pull quay.io/biocontainers/wtdbg:2.5--h577a1d6_6`（历史包名 wtdbg2 仍有 `wtdbg2:2.0--h470a237_0`）
* **Singularity**：<https://depot.galaxyproject.org/singularity/wtdbg%3A2.5--h577a1d6_6>
* **GitHub**：<https://github.com/ruanjue/wtdbg2>（releases：v2.5，预编译 `wtdbg-2.5_x64_linux.tgz`）
* 安装方式（本地）：`mamba create -n wtdbg2 -c conda-forge -c bioconda wtdbg=2.5`
