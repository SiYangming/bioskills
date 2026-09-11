# rmblast 软件模块（RMBlast：RepeatMasker 兼容版 NCBI BLAST+）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core / snakemake-wrappers 情况记录于此（均缺失，不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# rmblast / native — 建库与重复序列搜索驱动

**RMBlast**（"RepeatMasker compatible version of the standard NCBI BLAST+ suite"，bioconda 包名 `rmblast`、bioconda recipe 名 `RMBlast`）是 **NCBI BLAST+ 的补丁分支**：在标准 BLAST+ 套件基础上以 RMBlast patch（`isb-<ver>+-rmblast.patch`）加入 **`rmblastn`**（面向 **RepeatMasker** 的重复序列搜索优化），并随包提供 **`makeblastdb`** / `blastdbcmd` / `blastn` / `blastp` 等**全套 BLAST+ 二进制**。它是 **RepeatMasker**（`-e ncbi` / rmblast 引擎）与 **RepeatModeler** 的**搜索引擎依赖**——这两个工具在配置时把引擎指向本模块的安装路径即可，安装方式统一见本模块「环境安装」节（不在其它模块重复维护安装配方）；需要**标准 NCBI BLAST+**（无需 RepeatMasker 兼容语义的 blastn/blastp 等）见 [`modules/blast`](../blast/README.md)。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/rmblast / bioconda rmblast）提供；两个子命令分别包装官方入口：

## 能力

| 子命令            | 包装命令                                                                                | 作用                                                              | 线程                        |
| -------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------- | ------------------------- |
| `makeblastdb`  | `makeblastdb -in ref.fa -dbtype <nucl\|prot> -out <prefix>`                           | 为核苷酸/蛋白参考建 BLAST 库 → `<prefix>.n*`（nucl）/ `.p*`（prot）索引族       | 单线程建库（`--threads` 接受但不注入） |
| `rmblastn`     | `rmblastn -query q.fa -db <prefix> -outfmt 6 -num_threads N [-evalue E] [-out FILE]`  | 面向 RepeatMasker 的核苷酸 query 比对到核苷酸库（默认 `-outfmt 6` 表格；缺省 stdout） | ✅ 默认 4（注入 `-num_threads`）   |

## 用法

```bash
# CLI 直跑（RepeatMasker 引擎依赖的典型链路；先建库再检索）
python main.py makeblastdb refs.fa --dbtype nucl --out refs_db              # 建核苷酸库（位置参数或 --input）
python main.py rmblastn -query query.fa -db refs_db -o hits.tsv --outfmt 6 --evalue 1e-5 --threads 4
python main.py makeblastdb refs_prot.fa --dbtype prot --out prot_db         # 建蛋白库（覆盖 prot 建库路径）
python main.py rmblastn -query query.fa -db refs_db --outfmt "6 qseqid sseqid pident evalue bitscore" \
    --extra-args "-task rmblastn -max_target_seqs 5"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。`rmblastn` 把 `--threads` 注入 `-num_threads`；`makeblastdb` 为单线程建库，`--threads` 仅作为运行期选项被接受、不注入命令行（与官方 `makeblastdb` 无该选项一致，2026-09 核实）。

## 实战示例：建库 + rmblastn 检索（RepeatMasker / RepeatModeler 引擎链）

RMBlast 的典型用法是先 `makeblastdb` 建库、再用 `rmblastn` 做重复序列搜索；以下为原生 CLI 的典型用法，**等价能力由 `native/main.py` 的 `makeblastdb` / `rmblastn` 子命令提供**（见上「用法」）。

### 1. 建库（makeblastdb）

```bash
# 核苷酸库（供 rmblastn）：-dbtype nucl，产物 refs_db.nhr/.nin/.nsq …
makeblastdb -in refs.fa -dbtype nucl -out refs_db

# 多样本批量建库（每个参考一个库前缀）
for fa in refs/*.fasta; do
    name=$(basename "$fa" .fasta)
    makeblastdb -in "$fa" -dbtype nucl -out "db/${name}"
done
```

### 2. 重复序列搜索（rmblastn）

```bash
# 表格 6 输出到文件（-outfmt 6）
rmblastn -query query.fa -db refs_db -outfmt 6 -num_threads 4 -out hits.tsv

# 严格阈值 + 限制命中数
rmblastn -query query.fa -db refs_db -outfmt 6 -evalue 1e-5 -max_target_seqs 5 -out hits.tsv

# 逐样本批量检索（每个 query 一个结果文件）
for q in queries/*.fasta; do
    name=$(basename "$q" .fasta)
    rmblastn -query "$q" -db refs_db -outfmt 6 -num_threads 4 -out "${name}.hits.tsv"
done
# outfmt 6 默认列：qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore
```

### 3. 作为 RepeatMasker / RepeatModeler 的引擎

RepeatMasker（`-e ncbi` / rmblast 引擎）与 RepeatModeler 在配置时需要一个可用的 RMBlast 安装目录（其 `bin/` 中能找到 `rmblastn`）：把本模块「环境安装」得到的环境 `PATH` 指向它们，或在其 `configure` 时填写该目录即可。安装方式统一见下节。

### 4. 参数说明

| 参数                    | 说明                                                                    |
| --------------------- | --------------------------------------------------------------------- |
| `-in <file>`          |（makeblastdb）输入 FASTA；本驱动可用位置参数或 `--input`                             |
| `-dbtype nucl\|prot`  |（makeblastdb）库类型：`nucl`（供 rmblastn，默认）｜`prot`（供蛋白库）                     |
| `-out <prefix>`       |（makeblastdb）输出库前缀（basename）；rmblastn 的 `-db` 即此值                      |
| `-query <file>`       |（rmblastn）查询序列 FASTA                                                   |
| `-db <prefix>`        |（rmblastn）BLAST 库前缀（makeblastdb 的 `-out` 值）                            |
| `-outfmt <n\|自定义>`   | 结果格式，默认 `6`（表格）；如需列名可写 `"6 qseqid sseqid pident evalue bitscore"`      |
| `-evalue <E>`         | 期望值阈值（越小越严格）                                                          |
| `-num_threads N`      | 线程数（本驱动由 `--threads` 注入，默认 4）                                          |
| `-task rmblastn` 等   | 其它常用项经 `--extra-args` 透传                                             |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

RMBlast 上游同时提供**预编译二进制包**与**源码编译**两条官方路线——**本模块安装方式以上游官方预编译二进制包为首选**（§1），官方源码编译并列保留（§5）；官方容器/conda/brew（§2–§4）为备选。

### 1. 上游预编译二进制包（官方提供，首选，免 conda / 免编译）

RMBlast 上游**提供预编译二进制包**（见官网 <https://www.repeatmasker.org/rmblast/>），当前版本 **2.17.1**，包含 `rmblastn` 及 `makeblastdb` / `blastdbcmd` / `blastn` 等全套二进制。部署到用户前缀（免 root）：

```bash
mkdir -p ~/software && cd ~/software
# Linux x86_64（要求 GLIBC ≥ 2.34；更老的发行版如 Ubuntu 20.04 请改用官网 "Linux (Older OS versions)" 包）
curl -O https://www.repeatmasker.org/rmblast/rmblast-2.17.1+-x64-linux.tar.gz
tar zxf rmblast-2.17.1+-x64-linux.tar.gz                  # -> ~/software/rmblast-2.17.1/
echo 'export PATH=$PATH:~/software/rmblast-2.17.1/bin' >> ~/.bashrc && source ~/.bashrc
rmblastn -version    # 断言：rmblastn: 2.17.1+

# macOS arm64（预编译包未签名/未公证：首次运行需在「系统设置 → 隐私与安全性」放行）
# curl -O https://www.repeatmasker.org/rmblast/rmblast-2.17.1+-arm64-macosx.tar.gz
```

> 用于 RepeatMasker / RepeatModeler：重跑各自的 `configure`，把 BLAST 引擎 bin 指向 `~/software/rmblast-2.17.1/bin`（见 [`modules/repeatmasker`](../repeatmasker/README.md)、[`modules/repeatmodeler`](../repeatmodeler/README.md)）。
>
> 说明：官方预编译包为 **2.17.1**，且官网明示"不为所有平台构建"（现仅 Linux x86_64 与 macOS arm64）；bioconda 与官方镜像为 **2.17.0**，功能等价（2.17.1 修复 2.17.0 的 ungapped→gapped 性能回归）。

### 2. Conda / brew（包管理器安装，备选）

```bash
mamba create -n rmblast-native -c conda-forge -c bioconda rmblast=2.17.0
conda activate rmblast-native
rmblastn -version    # 断言（打印 rmblastn: 2.17.0+ 与 Package: rmblast 2.17.0）
```

```bash
# 或用 Homebrew（macOS / Linux；公式 rmblast 在 brewsci/bio tap，需先添加 tap）
# brew 同名核对：brewsci/bio formula rmblast 的 desc = "RepeatMasker compatible version of the standard NCBI BLAST suite"，即 RMBlast
# ⚠️ brew 当前 2.14.1，与上游预编译包 2.17.1 / 容器 2.17.0 有版本差异（版本以 formula 为准）；该公式 keg_only（与 blast 冲突）
brew tap brewsci/bio     # 首次使用需要
brew install rmblast
rmblastn -version        # 断言
```

### 3. Docker（官方镜像，备选）

```bash
docker pull quay.io/biocontainers/rmblast:2.17.0--hbfc2172_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/rmblast:2.17.0--hbfc2172_1 \
    makeblastdb -in /data/refs.fa -dbtype nucl -out /data/refs_db
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/rmblast:2.17.0--hbfc2172_1 \
    rmblastn -query /data/query.fa -db /data/refs_db -outfmt 6 -num_threads 4 -out /data/hits.tsv
```

### 4. Apptainer / Singularity（官方镜像，备选）

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull rmblast.sif docker://depot.galaxyproject.org/singularity/rmblast:2.17.0--hbfc2172_1
apptainer run -B $PWD:/data -H /data rmblast.sif rmblastn \
    -query /data/query.fa -db /data/refs_db -outfmt 6 -num_threads 4 -out /data/hits.tsv
```

### 5. 官方源码编译（NCBI BLAST+ 源码 + 官方补丁，保留路线）

不受支持平台或需自行编译时，走官方源码路线（NCBI BLAST+ **2.17.0** 源码 + RMBlast **2.17.1** 补丁），构建到用户前缀：

```bash
mkdir -p ~/software && cd ~/software
curl -O https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.17.0/ncbi-blast-2.17.0+-src.tar.gz
curl -O https://www.repeatmasker.org/rmblast/isb-2.17.1+-rmblast.patch.gz   # 与 BLAST+ 2.17.0 配套
tar zxf ncbi-blast-2.17.0+-src.tar.gz && cd ncbi-blast-2.17.0+-src
gunzip -c ../isb-2.17.1+-rmblast.patch.gz | patch -p1
cd c++ && ./configure --prefix="$HOME/software/rmblast-2.17.1" \
    --with-bin-release --without-boost --with-mt --without-krb5 --without-openssl \
    --with-projects=scripts/projects/rmblastn/project.lst
make -j 8 && make install
echo 'export PATH=$PATH:~/software/rmblast-2.17.1/bin' >> ~/.bashrc && source ~/.bashrc
rmblastn -version    # 断言：rmblastn: 2.17.1+
# 说明：亦可 brew tap brewsci/bio && brew install rmblast（已打包源码+补丁构建）
```

## 测试

```bash
cd modules/rmblast/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ 参数契约断言必跑；
# PATH 含 makeblastdb/rmblastn 时追加真跑最小链路（合成核苷酸库 → rmblastn 命中、合成蛋白库 → makeblastdb prot）；
#   未安装则 [SKIP]。
```

## 版本

* rmblast（RMBlast）**2.17.0**（bioconda::rmblast=2.17.0；官方镜像 tag `2.17.0--hbfc2172_1`），对应上游 NCBI BLAST+ **2.17.0** 源码 + RMBlast 补丁

* 上游官方**预编译二进制包**为 **2.17.1**（Linux x86_64 / macOS arm64，见官网 <https://www.repeatmasker.org/rmblast/>）；源码编译路线 = NCBI BLAST+ 2.17.0 源码 + `isb-2.17.1+-rmblast.patch.gz`

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/rmblast / depot.galaxyproject.org；本地不再自建容器）

* nf-core / snakemake-wrappers **官方均无** rmblast（见下「官方实现登记」）；brew（brewsci/bio）提供 **2.14.1**

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow）

**官方无** `modules/nf-core/rmblast`（2026-09 在线核实 `https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/rmblast` 返回 404）。需要 Nextflow 编排时，可用标准 BLAST+ 的官方 nf-core 子模块（`modules/nf-core/blast/*`，见 [`modules/blast`](../blast/README.md)），或以本模块 `rmblast_native` 为兜底。

### snakemake-wrappers（官方）

**官方无** `bio/rmblast`（2026-09 在线核实 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/rmblast` 返回 404；`bio/` 下有 `blast` 等但无 `rmblast`）。需要 Snakemake 时以本模块 `rmblast_native` 为兜底（或参照官方 `bio/blast` wrapper，见 [`modules/blast`](../blast/README.md)）。

## 版本差异声明（native / brew / 上游预编译）

| 实现                          | rmblast 版本 | 来源                                                                                                    |
| --------------------------- | ---------- | ----------------------------------------------------------------------------------------------------- |
| native（官方容器/conda）          | **2.17.0** | official biocontainer：quay.io/biocontainers/rmblast:2.17.0--hbfc2172_1 / bioconda rmblast=2.17.0       |
| 上游预编译二进制包（README §4）         | **2.17.1** | <https://www.repeatmasker.org/rmblast/rmblast-2.17.1+-x64-linux.tar.gz>（Linux x86_64）、`...-arm64-macosx.tar.gz`（macOS arm64） |
| 上游源码编译（README §5）            | **2.17.1** | NCBI BLAST+ 2.17.0 源码 + `isb-2.17.1+-rmblast.patch.gz`                                                |
| nf-core master              | —          | 官方无（modules/nf-core/rmblast 404）                                                                     |
| snakemake-wrappers          | —          | 官方无（bio/rmblast 404）                                                                                 |
| brew（brewsci/bio tap）       | 2.14.1     | brewsci/bio formula `rmblast`（desc = "RepeatMasker compatible version of the standard NCBI BLAST suite"） |

> 版本口径：容器/conda 为 **2.17.0**，上游预编译包与源码编译为 **2.17.1**（修复 2.17.0 的 ungapped→gapped 性能回归，检索结果无实质差异）；brew 为 **2.14.1**。RMBlast CLI 在同主版本内稳定，跨版本检索结果可能有细微差异；RepeatMasker 引擎依赖建议与所用安装路线保持一致。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# rmblast native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 rmblast-native.yml 后 mamba env create -f rmblast-native.yml；
# 在线推荐上方 mamba create 直装命令。rmblast=2.17.0 随包提供 rmblastn/makeblastdb 等全套二进制。
name: rmblast-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - rmblast=2.17.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/rmblast>

* **Docker**：`docker pull quay.io/biocontainers/rmblast:2.17.0--hbfc2172_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/rmblast%3A2.17.0--hbfc2172_1>

* 安装方式（本地）：`mamba create -n rmblast-native -c conda-forge -c bioconda rmblast=2.17.0`，或 `brew tap brewsci/bio && brew install rmblast`

* 上游官网：<https://www.repeatmasker.org/rmblast/> · 标准 NCBI BLAST+：见 [`modules/blast`](../blast/README.md)
