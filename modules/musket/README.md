# musket 软件模块

> 汇总说明：Musket（Liu Y. et al., Bioinformatics 2013, 29(3):308-315）是基于 k-mer spectrum 的
> 多阶段 Illumina 短读**替换错误修正**工具：master-slave 多线程模型，在流水线中依次应用三种修正
> 技术，支持 FASTA/FASTQ（含 gzip）多文库输入。官方发布站点为 SourceForge musket（最新
> **musket-1.1.tar.gz**，2013-10-09，112.1 kB；另有 1.0.3–1.0.8 历史发布与 utils/memusage.tar.gz），
> 官网文档 https://musket.sourceforge.net/homepage.htm （参数全表 + Typical Commands）。
> 本模块仅实现 `native/`（correct 一个技能子命令，承载官方主流程）；官方登记：**nf-core
> `modules/musket` 404、snakemake-wrappers `bio/musket` 404**（2026-09-08 GitHub API 核实）→ 不建
> nextflow/、snakemake/ 目录；官方渠道（bioconda → conda-forge → quay.io/biocontainers →
> quay.io/bioinfortools → depot.galaxyproject.org）亦**无任何 musket conda 包/官方镜像**（2026-09-08
> 逐渠道核实）→ `native/` 提供**自建** Dockerfile / Apptainer.def（debian:bookworm-slim +
> g++/make/zlib1g-dev + 官方源码 make，linux/amd64，仅录入不实构建）。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/musket/` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/musket> 返回 404）。
  Nextflow 场景请容器化（自建镜像）后走 native `correct` 子命令。

* **snakemake-wrappers**：`bio/musket` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/musket> 返回 404）。
  Snakemake 场景请在容器内 PATH 直调 `musket` 或走 native `correct` 子命令。

## native 实现

# musket / native — 多阶段 k-mer 谱错误修正驱动（v1.1）

Musket 1.1 的本地自包含实现（`source_type: custom`、`type: native`）。上游是**单条命令**工具
（无官方子命令、无 `--help`/`--version`），官方 CLI 形态（<https://musket.sourceforge.net/homepage.htm>）：

```
musket [-k <kmer_size> <est_kmer_count>] [-o <single_out> | -omulti <prefix>]
       [-p <threads>] [-inorder] [-lowercase] [-zlib <n>] [-maxtrim <n>]
       [-maxbuff <n>] [-multik <0|1>] [-maxerr <n>] [-maxiter <n>] [-minmulti <n>]
       <input1.fastq/fasta[.gz]> <input2...>
```

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `correct` | `musket [-k <kmer> <est>] [-o <file> \| -omulti <prefix>] -p <N> [-inorder] ... <reads...>` | 承载官方主流程：k-mer 谱错误修正。`--threads` 自动注入 `-p`；白名单参数给出才转发 |

> ⚠️ **参数语义澄清（以官方 README 为准，勿臆造）**：
> * `-k` 后必须跟**两个值**：第一值 k-mer 长度（默认 21），第二值估计的不同 k-mer 总数（默认
>   536870912）——教学文档所称「哈希表大小 50000000」实为该估计值；第二值**不影响正确性**，只
>   平衡 Bloom filter 与 hash table 之间的内存占用。
> * `-omulti <prefix>` 输出为 `<prefix>.0`、`<prefix>.1`、…（第 i 个输入对应第 i-1 个输出，从 0 起）；
>   `-o` 与 `-omulti` **互斥**。
> * `-p` 官方要求 **>=2**（默认 2）。
> * `-inorder` 保持输出顺序与输入一致——自 1.0.5 起 paired-end 多文库修正只需 `-omulti` +
>   `-inorder` 两选项（`-paired` 已被移除，等价于 `-inorder`）。
> * Makefile 宏 `MAX_KMER_SIZE` 默认 **28**（想用更大的 k 需改宏重编译）、`MAX_SEQ_LENGTH` 默认 **200**
>   （更长序列同理）。

## 用法

```bash
# CLI 直跑（等价官方命令；main.py 的 correct 只构造/执行 musket …；-k 两值/输入文件用长选项 + --reads）
python main.py correct --kmer-size 21 --est-kmer-count 50000000 --omulti out -p 4 --inorder \
    --reads f1.fastq f2.fastq
python main.py correct --kmer-size 21 --est-kmer-count 536870912 -o merged.fastq -p 8 \
    --reads lib1.fastq lib2.fastq                                              # -o 单文件合并
python main.py correct --omulti out --inorder \
    --reads f1_1.fastq f1_2.fastq f2_1.fastq f2_2.fastq                        # 默认 k/p（官方默认值）
python main.py correct --kmer-size 23 --est-kmer-count 268435456 -p 4 \
    --omulti out --inorder --reads sample.fastq.gz                             # gzip 输入

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands

# 只打印命令不执行（调试）
python main.py correct --kmer-size 21 --est-kmer-count 50000000 --omulti out -p 4 --inorder \
    --reads f1.fastq f2.fastq --dry-run
```

> `--threads` 自动注入官方 `-p`（官方要求 >=2；显式 `--threads` 优先，缺省取 meta `optimization`
> 默认 4）。Musket 官方无 `--version`/`--help`——可用性用「真实迷你修正冒烟」判定（见 install.sh
> 与 run_test.sh）。

## 实战示例：双文库 paired-end reads 错误修正

> 官方 README 的 Typical Commands（<https://musket.sourceforge.net/homepage.htm>）与教学场景典型用法
> 如下；等价能力由 `native/main.py` 的 `correct` 子命令提供（见上「用法」）。
> 容器内运行必须加 `-u $(id -u):$(id -g)`，否则输出文件归 root 持有。

### 1. 官方典型命令（单输出 / 多输出）

```bash
# 官方 Typical Commands（-o 单文件合并输出）
musket -k 21 536870912 -p 12 reads.fa reads2.fa -o output.fa
# 官方 paired-end 简化形态：只需 -omulti + -inorder（4 个输入 → 4 个输出）
musket reads_1.fa reads_2.fa reads1_1.fa reads1_2.fa -omulti output -inorder
```

### 2. 多文库错误修正 + 输出重命名 out.N（教学场景）

```bash
# 输入：两个文库（各双端）f1_1/f1_2、f2_1/f2_2；输出前缀 out →
#       out.0/out.1/out.2/out.3（与输入次序一一对应）
musket -k 21 50000000 -omulti out -p 4 -inorder \
    f1_1.fastq f1_2.fastq f2_1.fastq f2_2.fastq

# 输出重命名（按官方命名规则把 out.N 还原为可读的文件名：out.0/out.1 → 文库1 R1/R2 …）
mv out.0 f1_1.corrected.fastq
mv out.1 f1_2.corrected.fastq
mv out.2 f2_1.corrected.fastq
mv out.3 f2_2.corrected.fastq

# 批量场景（bash 循环；每文库对跑一次并重命名）
for lib in f1 f2 f3; do
    musket -k 21 50000000 -omulti ${lib}.out -p 4 -inorder \
        ${lib}_1.fastq ${lib}_2.fastq
    mv ${lib}.out.0 ${lib}_1.corrected.fastq
    mv ${lib}.out.1 ${lib}_2.corrected.fastq
done
```

### 3. 参数说明（main.py correct 白名单与官方一致）

| 参数（CLI / main.py） | 说明 | 默认 |
| --- | --- | --- |
| `-k <kmer> <est>` / `--kmer-size` + `--est-kmer-count` | k-mer 长度 + 估计的不同 k-mer 总数（后者只平衡 Bloom filter/hash 内存、不影响正确性） | 21 / 536870912 |
| `-o <file>` / `--output` | 单一输出文件（全部 reads 合并写入；与 `-omulti` 互斥） | — |
| `-omulti <prefix>` / `--omulti` | 多路输出前缀（第 i 输入 → `<prefix>.i-1`） | — |
| `-p <N>` / `--threads` | 线程数（官方要求 >=2） | 2（驱动默认 4） |
| `-inorder` / `--inorder` | 保持 reads 输出顺序与输入一致（PE 修正必需） | 关 |
| `-lowercase` / `--lowercase` | 修正碱基小写输出 | 关（大写） |
| `-zlib <n>` / `--zlib` | zlib 压缩输出（0=不压缩） | 0 |
| `-maxtrim <n>` / `--maxtrim` | 最多可修剪末端碱基数 | 0 |
| `-maxbuff <n>` / `--maxbuff` | 每 worker 消息缓冲容量（advanced） | 1024 |
| `-multik <0\|1>` / `--multik` | 启用多 k-mer 大小（advanced） | 关 |
| `-maxerr <n>` / `--maxerr` | 任意 #k 区域最大突变数（advanced） | 4 |
| `-maxiter <n>` / `--maxiter` | 每 k-mer 大小最大修正迭代数（advanced） | 2 |
| `-minmulti <n>` / `--minmulti` | 正确 k-mer 最低 multiplicity（仅非 multik） | 0 |

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道 2026-09 逐渠道核实**均无 musket conda 包/官方镜像**（bioconda/conda-forge API 均
`{"error":"musket" could not be found}`；quay.io/biocontainers、quay.io/bioinfortools 无仓库；
depot.galaxyproject.org 无 sif）→ 无官方镜像可直拉，`native/` 提供**自建配方** `Dockerfile` +
`Apptainer.def`（debian:bookworm-slim + apt 构建依赖 + 官方 SourceForge 源码 `make`，**不引入
miniconda**）。宿主机直跑 `main.py` 时按下面 1/4 安装 musket 与驱动环境。

### 1. Conda / brew（包管理器安装）

Musket **不在 bioconda，也不在 conda-forge**（2026-09-08 核实：`api.anaconda.org/package/bioconda/
musket` 与 `.../conda-forge/musket` 均返回 `{"error":"musket" could not be found}`，anaconda 页面
404）；homebrew 两源均无（homebrew-core `musket.json` 404、brewsci/bio `Formula/musket.rb` 404，
2026-09-08 核实），故**不提供 brew 块**。conda 只能建 python 驱动环境（本体仍走源码编译/容器）：

```bash
# conda 驱动 env（python=3.11 + pyyaml，供 main.py 自省/Schema；等价 native/environment.yml）
mamba create -n musket-native -c conda-forge python=3.11 pyyaml
# musket 本体：无 conda 包 → 见下方 §4 源码编译（或自建容器）
```

> 一键安装直接 `bash native/install.sh`（默认 source 路线装官方 1.1 源码到 `~/software/musket-1.1`
> 并写 PATH；`--method conda` 只建驱动 env；`bash native/install.sh --help` 看参数）。

### 2. Docker（自建镜像；无官方镜像可拉）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；amd64；context 必须是 modules/ 层以携带驱动代码）
docker build -t bioskills/musket:1.1 -f modules/musket/native/Dockerfile modules/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/musket:1.1 \
    -k 21 50000000 -p 4 -inorder -omulti /data/out /data/f1.fastq /data/f2.fastq
# 驱动 main.py（镜像内 base.py + 软件级 meta 已就位）：
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/musket:1.1 \
    /opt/skill/main.py correct --kmer-size 21 --est-kmer-count 50000000 --omulti /data/out \
    -p 4 --inorder --reads /data/f1.fastq /data/f2.fastq
```

> 镜像 ENTRYPOINT 为 `tini -- musket`；运行时直接传 musket 参数（`-k … -o/‑omulti …`），与
> docker run 追加的 argv 一一对应。

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 musket），**无法 `apptainer pull` 直拉**，本地构建：

```bash
# 构建（%files 源路径相对 apptainer build 时的 cwd=modules/）
cd modules && apptainer build musket-1.1.sif musket/native/Apptainer.def

# 运行（容器内 CLI = musket；挂载宿主目录读写产物）
apptainer run -B $PWD:/data -H /data musket-1.1.sif \
    -k 21 50000000 -p 4 -inorder -omulti /data/out /data/f1.fastq /data/f2.fastq
```

### 4. 二进制包安装（官方 release / 源码编译）

Musket 官方**仅发布 C++ 源码包、无预编译二进制 release**（sourceforge 文件区
musket-1.1.tar.gz / 1.0.3–1.0.8 / utils/memusage.tar.gz）。官方 README 编译 = 源码根目录 `make`：

```bash
# 0) 构建依赖：g++ + make + zlib（-zlib 输出 / gzip 输入需 zlib）
#    Debian/Ubuntu: sudo apt-get install -y --no-install-recommends build-essential make zlib1g-dev
#    macOS: Xcode Command Line Tools（系统自带 zlib）

# 1) 下载官方源码包 + 解压（2026-09-08 核实直链存在；官方文件名是 .tar.gz 不是 .tar.bz2）
mkdir -p ~/software && cd ~/software
wget https://downloads.sourceforge.net/project/musket/musket-1.1.tar.gz
tar zxf musket-1.1.tar.gz
cd musket-1.1 && make          # 官方 README：Type "make" in the root directory

# 2) 部署到用户前缀 + PATH + 冒烟（musket 无 --version/--help：无参运行/迷你修正判定可用性）
install -m 0755 musket ~/software/musket-1.1/bin 2>/dev/null || { mkdir -p ~/software/musket-1.1/bin && install -m 0755 musket ~/software/musket-1.1/bin/; }
echo 'export PATH=$HOME/software/musket-1.1/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
musket 2>&1 | grep -qiE 'usage|omulti|musket'   # 无参运行输出用法文本（行为未核实，宽松匹配）
```

> ⚠️ musket-1.1.tar.gz 的 **sha256 未核实**：SourceForge 不提供文件摘要、且无 bioconda/brew recipe
> 可参照 → 官方未公布即不编造；有安全校验需求时请自行对下载文件计算并留存。
> 💡 一键脚本走 `native/install.sh`（source 路线自动下载→make→部署→迷你修正冒烟断言，`--prefix`
> 可自定义；conda 分支仅建 python 驱动 env）。

## 测试

```bash
bash modules/musket/native/test/run_test.sh   # 自省 + argv 构造断言恒跑；musket 已装时真跑冒烟（合成双文库 FASTQ 修正）
```

## 版本与来源（2026-09-08 逐渠道核实，禁止编造版本/URL）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| SourceForge 文件区 | ✅ **musket-1.1.tar.gz**（2013-10-09，112.1 kB） | 另有 1.0.3–1.0.8 历史发布、utils/memusage.tar.gz；项目 Status: Beta，Last Update 2016-05-13 |
| 官方直链 | ✅ `https://downloads.sourceforge.net/project/musket/musket-1.1.tar.gz` | 2026-09-08 HEAD 302 → master.dl.sourceforge.net（真实存在） |
| 历史文档所记 `.tar.bz2` | ❌ `https://downloads.sourceforge.net/project/musket/musket-1.1.tar.bz2` HTTP 404 | 官方实际分发 **.tar.gz**，勿用 bz2 名 |
| 官网文档 | ✅ <https://musket.sourceforge.net/homepage.htm> | 参数全表 + Typical Commands + Change Log |
| license | ✅ SourceForge 项目页显示 **Apache License V2.0 + GPLv2** 双许可 | 源码包内 LICENSE 未下载核实 |
| sha256 | ❌ 官方未公布（SourceForge 不提供摘要；无 bioconda/brew recipe 参照） | **未核实**，不编造 |
| bioconda | ❌ 无包（api.anaconda.org `{"error":"musket" could not be found}`；页面 404） | 教学文档 `mamba install -c bioconda musket` 无法安装 |
| conda-forge | ❌ 无包（同 API 报错，2026-09-08） | — |
| quay.io/biocontainers | ❌ 无仓库（quay API 401；对照 fastuniq/samtools 200） | — |
| quay.io/bioinfortools | ❌ 无仓库（401） | — |
| depot.galaxyproject.org | ❌ `singularity/musket:1.1` HTTP 404 | — |
| Homebrew | ❌ homebrew-core `musket.json` 404；brewsci/bio `musket.rb` 404 | 两源均无 → 无 brew 块 |
| nf-core modules | ❌ 404（modules/nf-core/musket） | 无官方 Nextflow module → 流程场景降级 native |
| snakemake-wrappers | ❌ 404（bio/musket） | 无官方 Snakemake wrapper → 流程场景降级 native |
| bioconda-recipes 历史 | ❌ 无 recipes/musket（commits API 空） | 从未收录过 musket recipe |

* 官方渠道（bioconda → quay biocontainers → depot）**全无** → 判定「无官方维护」→ 走**自建兜底**
  路线，`native/` 维护 Dockerfile / Apptainer.def（`environment.dockerfile/apptainer_def` 已登记，
  `container_official` 无）。
* 编译兼容性（未核实）：2013 年代 C++ 源码，官方当时编译环境未在 README 说明；debian:bookworm
  的 g++ 12 下可能有新告警/需小修（本仓库只做录入，未实际构建验证；如遇报错请以源码为准调整）。

## 历史留存

原教学文档（旧法，仅追溯对照、不推荐）存在以下**与官方事实不符**之处，均不沿用、归档如下：
1. **源码名**：`https://sourceforge.net/projects/musket/files/musket-1.1.tar.bz2` —— 官方文件实际为
   **musket-1.1.tar.gz**（.tar.bz2 直链 404 核实不存在，2026-09-08）。
2. **conda 安装**：`mamba install -c bioconda -c conda-forge musket` —— bioconda/conda-forge **均无
   musket 包**（API 核实 `{"error":"musket" could not be found"}`），该命令会报 PackagesNotFoundError；
   安装请走官方源码 `make`（见上「环境安装 §4」）或自建容器。
3. **-k 语义**：`-k 21 50000000` 中 50000000 被记为「哈希表大小」——官方 README 语义为「估计的
   不同 k-mer 总数」（默认 536870912），只平衡 Bloom filter 与 hash table 之间内存、不影响正确性。
4. **输出命名**：`-omulti out` → `out.0`/`out.1`…（与输入文件一一对应）——与官方 README 一致，
   本模块沿用并给出「输出重命名 out.N」实战示例。
5. 安装路径 `/opt/biosoft`、`/home/train` 等 root 级硬编码不保留（用户前缀 `~/software/musket-1.1`）。
   使用形态 `musket -k 21 50000000 -omulti out -p 4 -inorder f1.fastq f2.fastq ...` 本身与官方 CLI
   兼容（-p>=2、-k 21 ≤ MAX_KMER_SIZE 28），已由「实战示例」承接。

## 性能优化约定

* **内存**：Musket 为 k-mer 计数/哈希类工具，内存占用高（Bloom filter + hash table 由 `-k` 第二值
  平衡；官方默认 536870912 为 2^29 级计数）→ `optimization.default_mem_mb=16384`（16 GB 级），
  超大文库请按数据量上调（官方未给精确公式，未核实）。
* **线程**：master-slave 多线程（官方 `-p` 要求 >=2）；驱动默认 4，`--threads` 显式优先注入 `-p`。
* `--tmpdir` 覆盖 `$TMPDIR`（`optimization.env_vars.TMPDIR`）；输出文件路径由 `-o`/`-omulti` 指定。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# musket native Conda 环境配方（native/environment.yml）
# 说明：bioconda / conda-forge 均无 musket 包（2026-09 API 核实）→ 本环境仅提供 python 驱动依赖；
#       musket 本体走官方源码编译（native/install.sh --method source 或 §4）或自建容器（§2/§3）
name: musket-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **SourceForge**：<https://sourceforge.net/projects/musket/>（项目页；文件区
  <https://sourceforge.net/projects/musket/files/>）
* **官网文档**：<https://musket.sourceforge.net/homepage.htm>（参数全表 = 官方 README；首页
  <https://musket.sourceforge.net/>）
* **官方源码直链**：<https://downloads.sourceforge.net/project/musket/musket-1.1.tar.gz>（sha256 未核实）
* **Bioconda**：无 musket 包（<https://anaconda.org/bioconda/musket> 404 + API
  `{"error":"musket" could not be found}`，2026-09-08 核实）
* **quay.io/biocontainers / quay.io/bioinfortools / depot.galaxyproject.org**：均无 musket（quay API
  401 = 仓库不存在、depot `singularity/musket:1.1` 404，2026-09-08 核实）
* **nf-core / snakemake-wrappers**：`modules/nf-core/musket` 与 `bio/musket` 均 404（2026-09-08）
* **Homebrew**：homebrew-core `musket.json` 404、brewsci/bio `musket.rb` 404（2026-09-08）→ 无公式
* **自建容器**：`modules/musket/native/Dockerfile`（`docker build -t bioskills/musket:1.1
  -f modules/musket/native/Dockerfile modules/`）、`modules/musket/native/Apptainer.def`
  （`cd modules && apptainer build musket-1.1.sif musket/native/Apptainer.def`）
* **引用论文**：Liu Y., Schroeder J., Schmidt B. Musket: a multistage k-mer spectrum based error
  corrector for Illumina sequence data. Bioinformatics 2013, 29(3): 308-315.
  <https://doi.org/10.1093/bioinformatics/bts690>
