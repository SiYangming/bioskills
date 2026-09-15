# genomethreader 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# genomethreader / native — 自包含相似性基因结构预测驱动

GenomeThreader 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

GenomeThreader 是一个用于基因预测和剪接比对的工具，BRAKER2 使用它进行蛋白序列比对。

三个子命令对应 `gth` / `gthconsensus` / `gthgetseq`：

| 子命令         | 命令（上游）                                                                                        | 作用                              |
| ----------- | ---------------------------------------------------------------------------------------------- | ------------------------------- |
| `align`     | `gth -genomic <fa> [-cdna <fa>] [-protein <fa>] [-species S] [-intermediate] [-gff3out] -o <out>` | 相似性剪接比对 / 基因结构预测                |
| `consensus` | `gthconsensus [-species S] [-gff3out] <intermediate...> -o <out>`                                 | 合并中间结果为 consensus 剪接比对          |
| `getseq`    | `gthgetseq -getgenomic\|-getprotein\|-getcdna <intermediate...>`                                  | 从中间结果提取 FASTA（写 stdout，可 `-o` 落盘） |

> 说明：`gth` 为单进程程序（无原生线程参数）；`--threads` / `--tmpdir` 为技能接口统一保留，
> 并行请按官方 FAQ 将输入文件分片后分别 `align -intermediate`，再 `gthconsensus` 合并。

## 用法

```bash
# CLI 直跑
python main.py align -genomic genome.fasta -protein proteins.fasta -species arabidopsis -o out.gff3
python main.py consensus out_1.gff3 out_2.gff3 -species arabidopsis -o consensus.gff3
python main.py getseq -getprotein consensus.gff3 -o proteins.fa

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：BRAKER2 同源蛋白比对（gth 作为蛋白 hints 引擎）

GenomeThreader 是 BRAKER2 中「同源蛋白证据」模式（`braker.pl --prot_seq ... --etpmode`）的蛋白比对引擎，
也常用于独立的外显子-内含子边界确认。以下为典型批量用法；等价能力由 `native/main.py` 的
`align` / `consensus` / `getseq` 子命令提供（见上「用法」）。

```bash
mkdir -p gth_out && cd gth_out

# 1. 蛋白序列对基因组的剪接比对（-gff3out 直接得到 GFF3；-intermediate 保留中间结果）
gth -genomic ../genome.fasta -protein ../homolog.fasta \
    -species arabidopsis -intermediate -gff3out -o homolog.gff3

# 2. 大规模时按官方 FAQ 分片并行：拆分蛋白输入 -> 分别 align -intermediate -> gthconsensus 合并
gt splitfasta -numperfile 1 -splitby size -targetsize 50MB ../homolog.fasta
for f in homolog.*.fasta; do
    gth -genomic ../genome.fasta -protein "$f" -species arabidopsis \
        -intermediate -gff3out -o "${f%.fasta}.gff3"
done
gthconsensus -species arabidopsis -gff3out *.gff3 -o homolog.consensus.gff3

# 3. 需要时从中间结果回取序列（如取蛋白序列核对）
gthgetseq -getprotein homolog.consensus.gff3 > back.fasta
```

参数说明：

| 参数                            | 说明                                                                     |
| ----------------------------- | ---------------------------------------------------------------------- |
| `-genomic <fa>`               | 基因组序列（必填）                                                              |
| `-cdna <fa>` / `-protein <fa>` | cDNA/EST 与蛋白序列（至少提供一个）                                                  |
| `-species <s>`                | 剪接位点模型：human/mouse/rat/chicken/drosophila/nematode/fission_yeast/aspergillus/arabidopsis/maize/rice/medicago |
| `-intermediate`               | 输出中间结果（便于分片并行后 `gthconsensus` 合并）                                       |
| `-gff3out`                    | 以 GFF3 格式输出                                                            |
| `-o <file>`                   | 输出文件                                                                   |

> 桥接句：上表的等价能力由 `native/main.py` 的 `align` / `consensus` / `getseq` 子命令提供，先 CLI 直跑、再按需接入 Agent。

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方**另有预编译二进制包**，两条官方路线（预编译包 / 源码编译）均保留。

### 1. 官方预编译二进制包（首选）

```bash
# 官方预编译二进制（仅 Linux x86_64；1.7.3）
wget https://genomethreader.org/distributions/gth-1.7.3-Linux_x86_64-64bit.tar.gz -P ~/software/
tar zxf ~/software/gth-1.7.3-Linux_x86_64-64bit.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/gth-1.7.3-Linux_x86_64-64bit/bin' >> ~/.bashrc
source ~/.bashrc
gth --version   # 断言
```

> 一键安装：`bash native/install.sh --method binary`（默认部署到 `~/software/gth-1.7.3-Linux_x86_64-64bit`，内嵌 sha256 校验）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码（GitHub genometools/genomethreader；与预编译包同一上游）
git clone https://github.com/genometools/genomethreader.git
cd genomethreader
make -j 4            # 生成 bin/gth、bin/gthconsensus、bin/gthgetseq 等
# 依赖：C/C++ 编译器、pthread；完整构建说明见仓库 README
```

### 3. Conda（包管理器安装，备选）

```bash
mamba create -n genomethreader -c conda-forge -c bioconda genomethreader=1.7.1
conda activate genomethreader
gth --version   # 断言
```

> ⚠️ 无 Homebrew 公式：已核实 homebrew-core（`formulae.brew.sh/api/formula/genomethreader.json` 404）与 brewsci/bio tap
> （`brewsci/homebrew-bio` Formula 目录无 `genomethreader`）两源均无，故不提供 `brew` 块。
>
> ⚠️ 版本差异：bioconda/quay/depot 官方镜像 pin 的是 **1.7.1**，官方预编译二进制为 **1.7.3**（相差一个 patch）。
> 一键安装直接 `bash native/install.sh`（有 conda/mamba 走 bioconda 1.7.1，否则 Linux 上走官方二进制 1.7.3）。

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/genomethreader:1.7.1--h503566f_7
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/genomethreader:1.7.1--h503566f_7 \
    gth -genomic /data/genome.fasta -protein /data/proteins.fasta -gff3out -o /data/out.gff3
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull genomethreader.sif docker://depot.galaxyproject.org/singularity/genomethreader:1.7.1--h503566f_7
apptainer run -B $PWD:/data -H /data genomethreader.sif \
    gth -genomic /data/genome.fasta -protein /data/proteins.fasta -gff3out -o /data/out.gff3
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证；gth 已安装时额外做版本冒烟
```

## 容器与 Conda 链接

* **官网**：http://genomethreader.org/

* **下载**：https://genomethreader.org/download.html
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/genomethreader/overview>

* **Docker**：`docker pull quay.io/biocontainers/genomethreader:1.7.1--h503566f_7`

* **Singularity**：<https://depot.galaxyproject.org/singularity/genomethreader%3A1.7.1--h503566f_7>

* **官方预编译二进制**：<https://genomethreader.org/distributions/gth-1.7.3-Linux_x86_64-64bit.tar.gz>

* 安装方式（本地）：`mamba create -n genomethreader -c conda-forge -c bioconda genomethreader=1.7.1`

## 版本

* 官方预编译二进制 1.7.3（Linux x86_64）；官方源码并列保留（genometools/genomethreader）

* 官方镜像 / conda：genomethreader 1.7.1（bioconda::genomethreader=1.7.1，tag 1.7.1--h503566f_7）

* nf-core / snakemake-wrappers：官方无模块 / 无 wrapper（2026-09-11 抓取 404）
