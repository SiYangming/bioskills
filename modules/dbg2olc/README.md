# dbg2olc 软件模块

> 汇总说明：本 README 合并各实现（native / 官方说明层）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# dbg2olc / native — 自包含混合组装驱动

DBG2OLC 的本地自包含实现（`source_type: custom`、`type: native`）；三段链路：短读 DBG 组装 → 长读 layout → Sparc consensus。

## 功能

DBG2OLC 是一个混合组装工具，先使用 De Bruijn Graph 组装二代数据得到 contigs，再利用三代数据进行 scaffold 连接。该工具包含三个主要步骤：SparseAssembler 组装、DBG2OLC Layout、Sparc Consensus。

三个子命令对应 DBG2OLC 混合组装的三段链路（共 3 个官方可执行/脚本，按子命令惰性解析）：

| 子命令               | 命令                                                                                                                               | 作用                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `sparseassembler` | `SparseAssembler LD <ld> k <k> g <g> NodeCovTh <n> EdgeCovTh <e> GS <gs> f <reads>...`                                             | 短读 de Bruijn 图组装 → `Contigs.txt` |
| `dbg2olc`         | `DBG2OLC LD <ld> k <k> AdaptiveTh <th> KmerCovTh <n> MinOverlap <l> RemoveChimera <c> Contigs <contigs> f <long reads>...`        | 长读 layout → `backbone_raw.fasta` + `DBG2OLC_Consensus_info.txt` |
| `sparc`           | `split_and_run_sparc.sh <backbone> <info> <ctg_pb> <outdir> <cores>`                                                              | Sparc + blasr consensus → `final_assembly.fasta` |

> ⚠️ `sparc` 依赖 blasr（第三步 consensus）；`split_and_run_sparc.sh` 为官方仓库 `utility/` 下的脚本。

## 用法

```bash
# 1) 短读 DBG 组装（k 参数扫描见「实战示例」）
python main.py sparseassembler illumina.1.fastq illumina.2.fastq --k 31 --g 15 --nodecov 1 --edgecov 0 --gs 1000000

# 2) 长读 layout
python main.py dbg2olc subreads.fasta --contigs Contigs.txt --adaptive-th 0.015 --kmer-cov-th 5 --min-overlap 50

# 3) Sparc consensus（--threads 注入 split_and_run_sparc.sh 核数）
python main.py sparc --backbone backbone_raw.fasta --info DBG2OLC_Consensus_info.txt --ctg-pb ctg_pb.fasta --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 当前对 `sparc` 生效）。

## 实战示例：混合组装三段链路

以下为文档中的典型 DBG2OLC 混合组装流程；等价能力由 `native/main.py` 的 `sparseassembler` / `dbg2olc` / `sparc` 子命令提供（见上「用法」）。

### 第 0 步：数据准备

```bash
mkdir -p DBG2OLC && cd DBG2OLC
ln -s ~/03.sequencing_data_quality_control/FindErrors/illumina.?.fastq ./
bam2fasta -o subreads -u ~/00.incipient_data/data_for_genome_assembling/m150226_221858_42237.subreads.bam
```

### 第 1 步：SparseAssembler（k-mer 长度参数扫描）

```bash
for ((i=31; i<=61; i=i+4))
do
    echo "mkdir k_$i; cd k_$i; SparseAssembler LD 0 k $i g 15 NodeCovTh 1 EdgeCovTh 0 GS 1000000 f ../illumina.1.fastq f ../illumina.2.fastq"
done > command.SparseAssembler.list
ParaFly -c command.SparseAssembler.list -CPU 8
for i in `ls k*/Contigs.txt`; do echo $i; genome_statistic.pl $i; done
mv k_31/* ./ && rm k* -rf     # 选定最优 k（示例 k=31）
```

### 第 2 步：DBG2OLC layout（AdaptiveTh / KmerCovTh / MinOverlap 调参）

```bash
DBG2OLC LD 0 k 17 AdaptiveTh 0.001 KmerCovTh 2 MinOverlap 20 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
# 扫描 AdaptiveTh（0.005/0.010/0.015/0.020）与 KmerCovTh/MinOverlap，按 N50 选最优
DBG2OLC LD 1 k 17 AdaptiveTh 0.015 KmerCovTh 5 MinOverlap 50 RemoveChimera 1 Contigs Contigs.txt f subreads.fasta
```

### 第 3 步：Sparc consensus

```bash
cp /opt/biosoft/DBG2OLC/utility/*.sh /opt/biosoft/DBG2OLC/utility/*.py ./
chmod 755 *.sh *.py
cat Contigs.txt subreads.fasta > ctg_pb.fasta
./split_and_run_sparc.sh backbone_raw.fasta DBG2OLC_Consensus_info.txt ctg_pb.fasta ./ 2 > cns_log.txt
```

### 参数说明

| 参数                        | 作用                 | 推荐范围       |
| ------------------------- | ------------------ | ---------- |
| `k`（SparseAssembler）      | k-mer 长度           | 31-61（奇数） |
| `NodeCovTh`               | 节点覆盖度阈值            | 1-4        |
| `EdgeCovTh`               | 边覆盖度阈值             | 0-3        |
| `k`（DBG2OLC）              | 比对 k-mer 长度        | 17         |
| `AdaptiveTh`              | 自适应阈值              | 0.001-0.02 |
| `KmerCovTh`               | k-mer 覆盖度阈值        | 2-5        |
| `MinOverlap`              | 最小重叠长度             | 20-50      |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有官方镜像/tag），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。官方同时提供两条安装路线（仓库内预编译二进制 / 源码编译），两条均保留。

### 1. 官方预编译二进制包（官方仓库 `compiled/`，首选）

DBG2OLC 官方仓库直接提供预编译二进制（`github.com/yechengxi/DBG2OLC/tree/master/compiled`：DBG2OLC / SparseAssembler / Sparc / SelectLongestReads / AssemblyStatistics），clone 后即可使用：

```bash
git clone --depth 1 https://github.com/yechengxi/DBG2OLC.git ~/software/DBG2OLC
cp ~/software/DBG2OLC/compiled/* ~/software/DBG2OLC/
echo 'export PATH=$PATH:~/software/DBG2OLC' >> ~/.bashrc && source ~/.bashrc
command -v DBG2OLC SparseAssembler   # 断言
```

> 一键安装：`bash native/install.sh --method binary`（默认前缀 `~/software/DBG2OLC`，用户级、免 root）。

### 2. 官方源码编译（并列保留）

官方 README 提供源码编译（3 个可执行程序）：

```bash
git clone https://github.com/yechengxi/DBG2OLC.git ~/software/DBG2OLC
cd ~/software/DBG2OLC
g++ -O3 -o SparseAssembler DBG2OLC.cpp
g++ -O3 -o DBG2OLC *.cpp
g++ -O3 -o Sparc *.cpp
echo 'export PATH=$PATH:~/software/DBG2OLC' >> ~/.bashrc && source ~/.bashrc
```

> 一键安装：`bash native/install.sh --method source`（g++ 编译到 `~/software/DBG2OLC/bin`）。

### 3. Conda（包管理器安装，备选）

```bash
mamba create -n dbg2olc -c conda-forge -c bioconda dbg2olc=20200723   # 官方日期式 pin
conda activate dbg2olc
command -v DBG2OLC SparseAssembler   # 断言（DBG2OLC 无 --version）
```

> 一键安装直接 `bash native/install.sh`（默认 auto：有 conda/mamba 走 bioconda，否则回退官方预编译二进制）。2026-09 核实 homebrew-core `formula/dbg2olc.json` 404、brewsci/bio `Formula/dbg2olc.rb` 404 → 本模块不写 brew 块。

### 4. blasr（consensus 步骤依赖）

```bash
mamba create -n blasr -c conda-forge -c bioconda blasr
```

### 5. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/dbg2olc:20200723--h077b44d_4
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/dbg2olc:20200723--h077b44d_4 \
    SparseAssembler LD 0 k 31 g 15 NodeCovTh 1 EdgeCovTh 0 GS 1000000 f /data/illumina.1.fastq f /data/illumina.2.fastq
```

### 6. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull dbg2olc.sif docker://depot.galaxyproject.org/singularity/dbg2olc:20200723--h077b44d_4
apptainer run -B $PWD:/data -H /data dbg2olc.sif \
    SparseAssembler LD 0 k 31 g 15 NodeCovTh 1 EdgeCovTh 0 GS 1000000 f /data/illumina.1.fastq f /data/illumina.2.fastq
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（三段链路）+ 自省；二分制未安装时跳过真实组装
```

## 容器与 Conda 链接

* **Github**：https://github.com/yechengxi/DBG2OLC

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/dbg2olc/overview>

* **Docker**：`docker pull quay.io/biocontainers/dbg2olc:20200723--h077b44d_4`

* **Singularity**：<https://depot.galaxyproject.org/singularity/dbg2olc%3A20200723--h077b44d_4>

* 安装方式（本地）：`mamba create -n dbg2olc -c conda-forge -c bioconda dbg2olc=20200723`

## 版本

* DBG2OLC 上游 GitHub 无正式版本号/tag；bioconda / quay.io 官方 pin 记为日期式 **20200723**

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/dbg2olc:20200723--h077b44d_4 / depot.galaxyproject.org；本地不自建容器）

* 2026-09 核实：nf-core `modules/nf-core/dbg2olc` 404、snakemake-wrappers `bio/dbg2olc` 404、homebrew-core / brewsci-bio 均无公式
