# blast 软件模块（NCBI BLAST+：基础序列比对与建库）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# blast / native — 建库与比对搜索驱动

BLAST+（**NCBI BLAST+**，alias **ncbi-blast+**；即 Debian 包名 `ncbi-blast+`、bioconda 包名 `blast`、nf-core 目录名 `blast`）是**序列相似性搜索的行业标准套件**：以 **`makeblastdb`** 为核苷酸/蛋白序列建立 BLAST 库，用 **`blastn`**（核苷酸 query vs 核苷酸库）、**`blastp`**（蛋白 query vs 蛋白库）等程序做局部比对搜索，默认输出表格 `-outfmt 6`。生物信息教学课件中，它是**基础序列比对/建库**的首选工具；同时它也是 **RNAmmer**（此外还需 HMMER 2.x，见 [`modules/hmmer`](../hmmer/README.md) 的「HMMER 2.x 遗留版（native2 实现）」章节）、**antiSMASH** 等工具的运行依赖——这些工具需要本工具，安装方式统一见本模块「环境安装」节（不在其它模块重复维护安装配方）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/blast / bioconda blast）提供；三个子命令分别包装官方三个入口：

## 能力

| 子命令            | 包装命令                                                                                       | 作用                                                     | 线程                        |
| -------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------ | ------------------------- |
| `makeblastdb`  | `makeblastdb -in ref.fa -dbtype <nucl\|prot> -out <prefix>`                                   | 为核苷酸/蛋白参考建 BLAST 库 → `<prefix>.n*`（nucl）/ `.p*`（prot）索引族 | 单线程建库（`--threads` 接受但不注入） |
| `blastn`       | `blastn -query q.fa -db <prefix> -outfmt 6 -num_threads N [-evalue E] [-out FILE]`            | 核苷酸 query 比对到核苷酸库（默认 `-outfmt 6` 表格；缺省 stdout）         | ✅ 默认 4（注入 `-num_threads`） |
| `blastp`       | `blastp -query q.fa -db <prefix> -outfmt 6 -num_threads N [-evalue E] [-out FILE]`            | 蛋白 query 比对到蛋白库（默认 `-outfmt 6` 表格；缺省 stdout）            | ✅ 默认 4（注入 `-num_threads`） |

## 用法

```bash
# CLI 直跑（教学典型链路；先建库再比对）
python main.py makeblastdb refs.fa --dbtype nucl --out refs_db              # 建核苷酸库（位置参数或 --input）
python main.py blastn -query query.fa -db refs_db -o hits.tsv --outfmt 6 --evalue 1e-5 --threads 4
python main.py makeblastdb refs_prot.fa --dbtype prot --out prot_db         # 建蛋白库
python main.py blastp -query query_prot.fa -db prot_db -o hits.tsv --threads 4
python main.py blastn -query query.fa -db refs_db --outfmt "6 qseqid sseqid pident evalue bitscore" \
    --extra-args "-max_target_seqs 5"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。`blastn`/`blastp` 把 `--threads` 注入 `-num_threads`；`makeblastdb` 为单线程建库，`--threads` 仅作为运行期选项被接受、不注入命令行（与官方 `makeblastdb` 无该选项一致）。

## 实战示例：序列建库与比对搜索（教学典型链路）

BLAST+ 教学典型命令为 `makeblastdb -in refs.fa -dbtype nucl -out refs_db` 与 `blastn -query query.fa -db refs_db -outfmt 6 -out hits.tsv`；以下为原生 CLI 的典型用法，**等价能力由 `native/main.py` 的 `makeblastdb` / `blastn` / `blastp` 子命令提供**（见上「用法」）。

### 1. 建库（makeblastdb）

```bash
# 核苷酸库（供 blastn）：-dbtype nucl，产物 refs_db.nhr/.nin/.nsq …
makeblastdb -in refs.fa -dbtype nucl -out refs_db

# 蛋白库（供 blastp）：-dbtype prot，产物 refs_db.phr/.pin/.psq …
makeblastdb -in refs_prot.fa -dbtype prot -out refs_prot_db

# 多样本批量建库（每个参考一个库前缀）
for fa in refs/*.fasta; do
    name=$(basename "$fa" .fasta)
    makeblastdb -in "$fa" -dbtype nucl -out "db/${name}"
done
```

### 2. 核苷酸比对（blastn）

```bash
# 表格 6 输出到文件（-outfmt 6；可追加列名自定义输出列）
blastn -query query.fa -db refs_db -outfmt 6 -num_threads 4 -out hits.tsv

# 严格阈值 + 限制命中数
blastn -query query.fa -db refs_db -outfmt 6 -evalue 1e-5 -max_target_seqs 5 -out hits.tsv

# 逐样本批量比对（每个 query 一个结果文件）
for q in queries/*.fasta; do
    name=$(basename "$q" .fasta)
    blastn -query "$q" -db refs_db -outfmt 6 -num_threads 4 -out "${name}.hits.tsv"
done
# outfmt 6 默认列：qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore
```

### 3. 蛋白比对（blastp）

```bash
blastp -query query_prot.fa -db refs_prot_db -outfmt 6 -num_threads 4 -out prot_hits.tsv
```

### 4. 参数说明

| 参数                    | 说明                                                                    |
| --------------------- | --------------------------------------------------------------------- |
| `-in <file>`          |（makeblastdb）输入 FASTA；本驱动可用位置参数或 `--input`                             |
| `-dbtype nucl\|prot`  |（makeblastdb）库类型：`nucl`（供 blastn，默认）｜`prot`（供 blastp）                  |
| `-out <prefix>`       |（makeblastdb）输出库前缀（basename）；blastn/blastp 的 `-db` 即此值                 |
| `-query <file>`       | 查询序列 FASTA                                                            |
| `-db <prefix>`        | BLAST 库前缀（makeblastdb 的 `-out` 值）                                      |
| `-outfmt <n\|自定义>`   | 结果格式，默认 `6`（表格）；如需列名可写 `"6 qseqid sseqid pident evalue bitscore"`      |
| `-evalue <E>`         | 期望值阈值（越小越严格）                                                          |
| `-num_threads N`      | 线程数（本驱动由 `--threads` 注入，默认 4）                                          |
| `-max_target_seqs` 等  | 其它常用项经 `--extra-args` 透传                                             |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像内含 blastn/blastp/makeblastdb/blastdbcmd/tblastn 等全套二进制）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n blast-native -c conda-forge -c bioconda blast=2.17.0
conda activate blast-native
blastn -version    # 断言（打印 blastn: 2.17.0+ 与 Package: blast 2.17.0）
```

```bash
# 或用 Homebrew（macOS / Linux；公式 blast 在 homebrew-core，无需额外 tap）
# brew 同名核对：core formula blast 的 desc = "Basic Local Alignment Search Tool"（即 NCBI BLAST+），版本 2.17.0 与 meta 登记一致
brew install blast
blastn -version    # 断言
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/blast:2.17.0--hb02a186_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/blast:2.17.0--hb02a186_1 \
    makeblastdb -in /data/refs.fa -dbtype nucl -out /data/refs_db
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/blast:2.17.0--hb02a186_1 \
    blastn -query /data/query.fa -db /data/refs_db -outfmt 6 -num_threads 4 -out /data/hits.tsv
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull blast.sif docker://depot.galaxyproject.org/singularity/blast:2.17.0--hb02a186_1
apptainer run -B $PWD:/data -H /data blast.sif blastn \
    -query /data/query.fa -db /data/refs_db -outfmt 6 -num_threads 4 -out /data/hits.tsv
```

### 4. 二进制包安装（官方预编译二进制）

NCBI 官方提供**预编译二进制**（Linux/macOS，x64 与 aarch64），可直接部署到用户前缀：

**下载页**：<https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/>

```bash
# 按平台选择：-x64-linux / -x64-macosx / -aarch64-linux / -aarch64-macosx（与 software_versions 对齐 2.17.0）
wget https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/ncbi-blast-2.17.0+-x64-linux.tar.gz -P ~/software/
tar zxf ~/software/ncbi-blast-2.17.0+-x64-linux.tar.gz -C ~/software/     # -> ~/software/ncbi-blast-2.17.0+/
echo 'export PATH=$PATH:~/software/ncbi-blast-2.17.0+/bin' >> ~/.bashrc && source ~/.bashrc
blastn -version    # 断言：blastn: 2.17.0+
# 同目录另有 -aarch64-*.tar.gz（ARM）与 -universal-macosx.tar.gz（macOS 通用）；win64 见官网
```

## 测试

```bash
cd modules/blast/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ 参数契约断言必跑；
# PATH 含 makeblastdb/blastn/blastp 时追加真跑最小链路（合成核苷酸库 → blastn 命中、
#   合成蛋白库 → blastp 命中）；未安装则 [SKIP]。
```

## 版本

* blast（NCBI BLAST+）**2.17.0**（bioconda::blast=2.17.0，2026-03 起发布；官方镜像 tag `2.17.0--hb02a186_1`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/blast / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方子模块、snakemake-wrappers 与 brew 均 pin/提供 **2.17.0**（三方与 native 一致，见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/blast/` **存在**（2026-09 在线核实，按在线目录登记；以官方在线目录为准）：

| 子模块               | environment.yml 关键 pin      | 作用（据 nf-core meta）                          |
| ----------------- | -------------------------- | ------------------------------------------ |
| `blastn`          | bioconda::blast=2.17.0     | 核苷酸 query 比对核苷酸库（输入 fasta + db → 比对结果）       |
| `blastp`          | bioconda::blast=2.17.0     | 蛋白 query 比对蛋白库                             |
| `blastdbcmd`      | bioconda::blast=2.17.0     | 从 BLAST 库提取序列/条目                          |
| `makeblastdb`     | bioconda::blast=2.17.0     | 建核苷酸/蛋白 BLAST 库                            |
| `tblastn`         | bioconda::blast=2.17.0     | 蛋白 query 比对翻译后的核苷酸库                        |
| `updateblastdb`   | bioconda::blast=2.17.0     | 更新已有 BLAST 库                               |

> ⚠️ 执行请用 `nf modules install nf-core blast blastn blastp blastdbcmd makeblastdb tblastn updateblastdb`（安装到项目自身 `modules/nf-core/`，不要直接引用本仓库示例），随后：
>
> ```nextflow
> include { BLAST_BLASTN } from '../modules/nf-core/blast/blastn/main'
> include { BLAST_MAKEBLASTDB } from '../modules/nf-core/blast/makeblastdb/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/blast | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方存在，扁平 wrapper）

官方 snakemake-wrappers **有** `bio/blast/blastn` 与 `bio/blast/makeblastdb`（**扁平 wrapper**：`wrapper.py` + `environment.yaml` + `meta.yaml` + `test`，无子目录；2026-09 在线核实，v9.17.1 tag 含该 wrapper；environment.yaml pin `blast=2.17.0`）。可直接粘贴的规则示例：

```python
rule blast_makeblastdb:
    input:
        fasta="refs.fa"
    output:
        db="refs_db.nsq",            # 扩展名 .n* 决定 -dbtype nucl；.p* 决定 prot（wrapper 去扩展名取库前缀）
    params:
        "-parse_seqids",             # wrapper 的 params 为 raw 字符串，直接拼到 makeblastdb 命令
    log:
        "logs/makeblastdb.log",      # wrapper 用 -logfile 写入
    wrapper: "v9.17.1/bio/blast/makeblastdb"

rule blast_blastn:
    input:
        query="query.fa",
        blastdb="refs_db.nsq",       # 指向库文件之一；wrapper 会去掉扩展名取库前缀传给 -db
    output:
        "hits.tsv",                  # wrapper 用 -out {output[0]}
    params:
        format="6",                  # -outfmt（如 "6 qseqid sseqid pident evalue bitscore"）
        extra="",                    # 附加参数（-evalue/-max_target_seqs 等）
    threads: 8
    log:
        "logs/blastn.log",
    wrapper: "v9.17.1/bio/blast/blastn"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/blast/blastn`、`v9.17.1/bio/blast/makeblastdb`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

## 版本差异声明（native / nf-core / snakemake-wrappers / brew）

| 实现                 | blast 版本  | 来源                                                                                                              |
| ------------------ | --------- | --------------------------------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **2.17.0** | official biocontainer：quay.io/biocontainers/blast:2.17.0--hb02a186_1 / bioconda blast=2.17.0                    |
| nf-core master     | 2.17.0    | bioconda::blast=2.17.0（modules/nf-core/blast/{blastn,blastp,blastdbcmd,makeblastdb,tblastn,updateblastdb}/environment.yml） |
| snakemake-wrappers | 2.17.0    | bioconda blast=2.17.0（bio/blast/{blastn,makeblastdb}/environment.yaml；v9.17.1 tag）                              |
| brew（homebrew-core）| 2.17.0    | homebrew-core formula `blast`（desc = "Basic Local Alignment Search Tool"，与 meta 登记一致）                          |

> 四方版本一致（均 2.17.0），可自由混用；BLAST+ CLI 在同主版本内稳定，若上游 bump 到 2.18.x，请同步刷新 native 镜像 tag（quay/depot）与 nf-core / wrapper 的 environment pin。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# blast native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 blast-native.yml 后 mamba env create -f blast-native.yml；
# 在线推荐上方 mamba create 直装命令。blast=2.17.0 随包提供 blastn/blastp/makeblastdb 等全套二进制。
name: blast-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - blast=2.17.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/blast>

* **Docker**：`docker pull quay.io/biocontainers/blast:2.17.0--hb02a186_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/blast%3A2.17.0--hb02a186_1>

* 安装方式（本地）：`mamba create -n blast-native -c conda-forge -c bioconda blast=2.17.0`，或 `brew install blast`

* 上游官网：<https://blast.ncbi.nlm.nih.gov/Blast.cgi> · 官方二进制下载：<https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/>
