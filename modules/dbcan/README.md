# dbcan 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
> 官方 nf-core / snakemake-wrappers **均无** dbcan（2026-09 抓取 404），无官方登记层。
> **本模块为「数据库 + 脚本」包**（非单一二进制）：走 13.md 经典 dbCAN V9 路线，数据库需单独下载并本地建库。

---

## native 实现

# dbcan / native — 自包含 CAZy 注释驱动（dbCAN V9）

dbCAN 的本地自包含实现（`source_type: custom`、`type: native`，数据库版本 V9 /
CAZyDB.07312020）。基于 HMMER `hmmscan` + DIAMOND `blastp` + `hmmscan-parser.sh` 完成 CAZy 家族注释。

## 功能

| 子命令              | 底层命令                                                                                                              | 作用                    |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------- |
| `build_hmm`      | `hmmpress <hmm_db>`                                                                                               | 建立 dbCAN HMM 数据库      |
| `build_blastdb`  | `makeblastdb -in <fasta> -dbtype prot -title <t> -parse_seqids -out <db> -logfile <log>`                          | 建立 CAZy 蛋白 BLAST 库     |
| `build_diamond`  | `diamond makedb --in <fasta> --db <db>`                                                                           | 建立 CAZy DIAMOND 库      |
| `hmmscan`        | `hmmscan --cpu N -E <e> --domE <de> --domtblout <out> <hmm_db> <fasta>`                                            | HMM 方法扫描（域级 domtblout） |
| `diamond_blastp` | `diamond blastp --db <db> --query <fasta> --out <out> --outfmt <n> ... --threads N`                               | BLAST 方法比对            |
| `parse_hmmscan`  | `hmmscan-parser.sh <domtblout>`                                                                                   | 解析 domtblout 得 CAZy 家族注释 |

> 各子命令自动注入线程：`hmmscan` 用 `--cpu`，`diamond blastp` 用 `--threads`。

## 用法

```bash
# 建库（一次性）
python main.py build_hmm --hmm_db dbCAN-fam-HMMs.txt
python main.py build_blastdb --fasta CAZyDB.07312020.fa --blast_db CAZyDB.07312020 --title CAZyDB.07312020
python main.py build_diamond --fasta CAZyDB.07312020.fa --db CAZyDB.07312020

# 注释（对应 13.md「十五、CAZy注释」）
python main.py hmmscan --hmm_db dbCAN-fam-HMMs.txt --fasta proteins.fasta \
    --domtblout hmmscan.domtbl -E 1e-3 --domE 1e-3 --threads 8
python main.py diamond_blastp --db CAZyDB.07312020 --fasta proteins.fasta \
    --output diamond.xml --outfmt 5 --sensitive --max-target-seqs 500 --evalue 1e-5 --min_id 20 --threads 8
python main.py parse_hmmscan --domtblout hmmscan.domtbl -o hmmscan.out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 建库步骤与数据体积

dbCAN V9 为**数据库 + 脚本**包，使用前必须下载并建库（体积较大，请预留磁盘）：

### 1. 下载（bcb.unl.edu/dbCAN2/download/）

| 文件                          | 用途                |
| --------------------------- | ----------------- |
| `dbCAN-HMMdb-V9.txt`        | CAZy 家族 HMM 模型库    |
| `CAZyDB.07312020.fa`        | CAZy 蛋白序列库（2020-07-31） |
| `Databases/V9/hmmscan-parser.sh` | hmmscan 结果解析脚本     |
| `Databases/V9/readme.txt`   | 说明                |

```bash
mkdir -p ~/software/dbCAN_v9.0 && cd ~/software/dbCAN_v9.0
wget http://bcb.unl.edu/dbCAN2/download/dbCAN-HMMdb-V9.txt
wget http://bcb.unl.edu/dbCAN2/download/CAZyDB.07312020.fa
wget http://bcb.unl.edu/dbCAN2/download/Databases/V9/hmmscan-parser.sh
wget http://bcb.unl.edu/dbCAN2/download/Databases/V9/readme.txt
ln -s dbCAN-HMMdb-V9.txt dbCAN-fam-HMMs.txt
perl -p -i -e 's/\|\s*$/\n/ if m/^>/' CAZyDB.07312020.fa   # 修复 FASTA 头部结尾 " |"
```

### 2. 建库

```bash
hmmpress dbCAN-fam-HMMs.txt
makeblastdb -in CAZyDB.07312020.fa -dbtype prot -title CAZyDB.07312020 \
    -parse_seqids -out CAZyDB.07312020 -logfile CAZyDB.07312020.makeblastdb.log
diamond makedb --in CAZyDB.07312020.fa --db CAZyDB.07312020
```

> 依赖外部工具：**HMMER**（`hmmpress` / `hmmscan`）、**NCBI BLAST+**（`makeblastdb`）、**DIAMOND**（`diamond`）。
> 数据体积：HMM 模型库 + CAZy 蛋白序列库体量较大，建库产物（hmmpress 的 `.h3*`、BLAST 的 `.p*`、
> DIAMOND 的 `.dmnd`）会再增，官方下载页未标注精确体积，建议预留**数 GB** 磁盘。

## 实战示例：HMM + BLAST 双方法合并（对应 13.md「十五、CAZy注释」）

CAZy 注释推荐 HMM 方法（`hmmscan`，灵敏）与 BLAST 方法（`diamond`，快速）各跑一遍再合并。等价能力由
`native/main.py` 的 `hmmscan` / `diamond_blastp` / `parse_hmmscan` 子命令提供（见上「用法」）。

```bash
mkdir -p /path/13.functional_annotation/cazyme && cd $_

# 方法1：HMM（hmmscan）
hmmscan --cpu 8 -E 1e-3 --domE 1e-3 --domtblout hmmscan.domtbl \
    ~/software/dbCAN_v9.0/dbCAN-fam-HMMs.txt ../proteins.fasta

# 方法2：BLAST（diamond blastp）
diamond blastp --db ~/software/dbCAN_v9.0/CAZyDB.07312020 --query ../proteins.fasta \
    --out diamond.xml --outfmt 5 --sensitive --max-target-seqs 500 --evalue 1e-5 --id 20 \
    --tmpdir /dev/shm --index-chunks 1

# 解析 + 合并（dbcan_combine.pl 来自 dbCAN 流程脚本）
parsing_blast_result.pl --no-header --evalue 1e-5 --HSP-num 1 diamond.xml > blastp.outfmt6
dbcan_combine.pl --query ../proteins.fasta \
    --CAZy_blastDB ~/software/dbCAN_v9.0/CAZyDB.07312020.fa \
    --threshold_file_in ~/software/dbCAN_v9.0/out90.threshold.tab hmmscan.domtbl blastp.outfmt6
```

## 环境安装（官方数据库/脚本下载 + 本地建库；Conda / 官方镜像并列）

本模块主路线为**官方数据库/脚本下载 + 本地建库**（经典 dbCAN V9）；官方另在 bioconda/quay 提供
`dbcan` 包（实为 **run_dbcan**，dbCAN2 下游封装，当前 5.2.9，与经典 V9 脚本非同一代），可直接拉镜像/conda。
官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均有 dbcan（run_dbcan）**，
依规范本地**不维护 Dockerfile/Apptainer.def**；经典 V9 数据库体积大，不入镜像、单独下载。

### 1. 官方数据库 + 脚本下载与本地建库（首选，经典 V9 路线）

```bash
# 一键执行下载 + 建库（部署到 ~/software/dbCAN_v9.0）
bash native/install.sh
# 或手动（见上「建库步骤与数据体积」）
```

> `native/install.sh` 现代规范：默认 `--method db`（下载 dbCAN-HMMdb-V9 / CAZyDB.07312020.fa /
> hmmscan-parser.sh 并执行 hmmpress / makeblastdb / diamond makedb）；`--method conda` 安装 run_dbcan；
> `--no-build` 可只下载不建库。用法：`bash native/install.sh --help`。

### 2. Conda（run_dbcan，包管理器安装，备选）

```bash
mamba create -n dbcan-native -c conda-forge -c bioconda dbcan=5.2.9
conda activate dbcan-native
run_dbcan --help   # 断言
```

> brew：homebrew-core 与 brewsci/bio 均无 dbcan 公式（2026-09 核实 404），故不提供 brew 安装块。
> 注意：`dbcan=5.2.9` 为 run_dbcan（下一代封装）；经典 V9 脚本/数据库请走上方 §1。

### 3. Docker（官方镜像，run_dbcan）

```bash
docker pull quay.io/biocontainers/dbcan:5.2.9--pyhdfd78af_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/dbcan:5.2.9--pyhdfd78af_0 \
    run_dbcan --help
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull dbcan.sif docker://depot.galaxyproject.org/singularity/dbcan:5.2.9--pyhdfd78af_0
apptainer run -B $PWD:/data -H /data dbcan.sif run_dbcan --help
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（真实注释需下载数据库并建库）
```

## 版本

* dbCAN V9（数据库包：dbCAN-HMMdb-V9 / CAZyDB.07312020 / hmmscan-parser V9；对应 13.md「十五、CAZy注释」）

* 构建路线：经典 V9 数据库/脚本从 bcb.unl.edu/dbCAN2 下载并本地建库；run_dbcan 由官方镜像/conda 提供
  （quay.io/biocontainers/dbcan:5.2.9--pyhdfd78af_0 / depot.galaxyproject.org）

* 官方登记：nf-core `dbcan` **404**、snakemake-wrappers `bio/dbcan` **404**（2026-09 抓取）——均无官方实现

* brew：homebrew-core / brewsci-bio 均无公式（404）

* 容器说明：官方容器名为 dbcan（=run_dbcan，5.2.9），与经典 V9 脚本非同一代，二者可并存

## 容器与 Conda 链接

* **dbCAN 官网**：<http://bcb.unl.edu/dbCAN2/index.php>（下载页 <http://bcb.unl.edu/dbCAN2/download/>）

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/dbcan/overview>

* **Docker**：`docker pull quay.io/biocontainers/dbcan:5.2.9--pyhdfd78af_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/dbcan%3A5.2.9--pyhdfd78af_0>

* 安装方式（本地）：经典 V9 → `bash native/install.sh`；run_dbcan → `mamba create -n dbcan -c conda-forge -c bioconda dbcan=5.2.9`
