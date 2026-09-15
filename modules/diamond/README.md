# diamond 软件模块

> 汇总说明：本 README 合并各实现（native/官方 wrapper）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# diamond / native — 自包含蛋白比对驱动

DIAMOND 的本地自包含实现（`source_type: custom`、`type: native`）。比对速度比 BLAST 快数百倍，常用于大规模蛋白序列注释。

## 功能

DIAMOND 是一款高速的蛋白质序列比对工具，比 BLAST 快 500-20,000 倍，同时保持相似的灵敏度。主要用于大规模蛋白质序列的同源搜索，适合宏基因组和大数据量的功能注释分析。

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `makedb` | `diamond makedb --threads N --db <db> --in <protein.fasta>` | 为蛋白 FASTA 建库 |
| `blastp` | `diamond blastp --db <db> --query <q> --out <out> --outfmt 5 --sensitive --threads N` | 蛋白 vs 蛋白库比对 |
| `blastx` | `diamond blastx --db <db> --query <q> --out <out> --outfmt 6 --threads N` | 核酸 vs 蛋白库比对 |

## 用法

```bash
# CLI 直跑
python main.py makedb --db uniprot_sprot --in uniprot_sprot.fasta --threads 8
python main.py blastp --db uniprot_sprot --query longest_orfs.pep --out blast.xml \
    --outfmt 5 --sensitive --max-target-seqs 20 --evalue 1e-5 --min-id 20 --threads 8
python main.py blastx --db nr --query transcripts.fa --out blastx.tsv --outfmt 6 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：SwissProt 同源搜索（TransDecoder ORF 过滤）

DIAMOND 比 BLAST 快数百倍，是 TransDecoder 同源搜索方法推荐的比对器。以下为文档典型用法；等价能力由 `native/main.py` 的 `makedb` / `blastp` 子命令提供（见上「用法」）。

### 1. 建库

```bash
gzip -dc ~/software/uniprot_sprot.fasta.gz > uniprot_sprot.fasta
diamond makedb --threads 8 --db uniprot_sprot --in uniprot_sprot.fasta
```

### 2. 比对（输出 BLAST XML）

```bash
diamond blastp --db uniprot_sprot --query longest_orfs.pep \
    --out blast.xml --outfmt 5 --sensitive --max-target-seqs 20 \
    --evalue 1e-5 --id 20 --tmpdir /dev/shm --index-chunks 1
```

### 3. 解析结果并过滤 ORF

```bash
parsing_blast_result.pl --no-header --max-hit-num 20 --query-coverage 0.2 --subject-coverage 0.1 blast.xml > blastp.outfmt6
TransDecoder.Predict -t Unigene.fasta --retain_pfam_hits pfam.domtbl --retain_blastp_hits blastp.outfmt6
```

### 4. 参数说明

| 参数 | 说明 |
| --- | --- |
| `--db` | DIAMOND 数据库（makedb 输出 / 比对输入） |
| `--in` | 建库输入蛋白 FASTA |
| `--query` | 查询序列（blastp 蛋白 / blastx 核酸） |
| `--out` | 比对结果输出文件 |
| `--outfmt` | 输出格式，5=XML，6=tabular |
| `--sensitive` | 更灵敏（更慢）的搜索模式 |
| `--max-target-seqs` | 每条 query 最大命中数 |
| `--evalue` | E-value 阈值 |
| `--id` | 最小一致性百分比 |
| `--tmpdir` | 临时目录（大库比对时建议指向内存盘 /dev/shm） |
| `--index-chunks` | 索引分块数 |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方同时提供 linux-x64 预编译二进制包与源码编译两条路线（均已核实，预编译为推荐首选；v2.0.14 无 macOS 预编译资产，macOS 用户请走 conda）。

### 1. 官方预编译二进制包（首选）

```bash
# 官方 release 预编译包（linux-x64）
wget https://github.com/bbuchfink/diamond/releases/download/v2.2.4/diamond-linux64.tar.gz -P ~/software/
tar zxf ~/software/diamond-linux64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/' >> ~/.bashrc
source ~/.bashrc
diamond version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `diamond`，无 conda 时下载官方 linux-x64 预编译包到 `~/software/diamond-<ver>` 并写 PATH；版本默认 2.0.14，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 需要 cmake + C++ 编译器 + zlib
git clone https://github.com/bbuchfink/diamond.git
cd diamond
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=~/software/diamond-2.0.14
make -j 4
make install
export PATH=$PATH:~/software/diamond-2.0.14/bin && diamond version   # 断言
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n diamond-native -c conda-forge -c bioconda diamond=2.0.14
conda activate diamond-native
diamond version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install diamond
diamond version   # 断言（brew 当前 2.2.6，与 meta 登记 2.0.14 略有差异，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/diamond:2.0.14--hb97b32f_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/diamond:2.0.14--hb97b32f_1 \
    blastp --db /data/uniprot_sprot --query /data/longest_orfs.pep --out /data/blast.xml --outfmt 5 --threads 8
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull diamond.sif docker://depot.galaxyproject.org/singularity/diamond:2.0.14--hb97b32f_1
apptainer run -B $PWD:/data -H /data diamond.sif version
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（makedb/blastp/blastx），无需已安装 diamond
```

## 版本

* diamond 2.0.14（bioconda::diamond=2.0.14；quay tag `2.0.14--hb97b32f_1`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/diamond / depot.galaxyproject.org；本地不再自建容器）；官方另提供 linux-x64 预编译二进制包与源码编译路线

## 容器与 Conda 链接

* **Github**：https://github.com/bbuchfink/diamond

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/diamond/overview>

* **Docker**：`docker pull quay.io/biocontainers/diamond:2.0.14--hb97b32f_1`

* **Singularity**：<https://depot.galaxyproject.org/singularity/diamond%3A2.0.14--hb97b32f_1>

* 安装方式（本地）：`mamba create -n diamond -c conda-forge -c bioconda diamond=2.0.14`

***

## 官方实现登记（不建目录）

* **nf-core modules**：`modules/nf-core/diamond/{blastp,blastx,cluster,deepclust,linclust,makedb}`，pin `bioconda::diamond=2.2.1`。执行前请 `nf-core modules install diamond blastp blastx makedb` 安装到项目自身目录，不要直接引用本仓库示例。

* **snakemake-wrappers**：`bio/diamond/{blastp,blastx,makedb}`，环境 pin `diamond=2.2.6`。运行时靠 `wrapper: "v9.17.1/bio/diamond/blastp"` 句柄解析，不要把本地示例当 `wrapper_path`。
