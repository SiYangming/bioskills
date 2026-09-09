# lordec 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09-08 逐渠道核实）。

***

## native 实现

# lordec / native — Illumina 短读纠错 PacBio/长读驱动（v0.9）

LoRDEC（Salmela & Rivals 2014, *Bioinformatics* 30:3506）的本地驱动实现（`source_type: custom`、
`type: native`），命令逻辑对齐官方 v0.9 CLI：用 Illumina（或任意低错误率短读）建 succinct De
Bruijn Graph，为长读（PacBio/ONT）的每个错误区在图中寻找修正路径并回代。

## 能力

| 子命令 | 二进制 | 说明 | 关键参数 |
| --- | --- | --- | --- |
| `correct` | `lordec-correct` | 主纠错：短读建 DBG → 纠正长读错误区（替换/插入/删除） | `-2`（短读，可双端逗号两文件）、`-i`、`-k`、`-s`、`-o`、`-T`（线程） |
| `trim` | `lordec-trim` | 修剪 corrected reads 头尾未能纠正（小写）区段 | `-i`、`-o`（单线程） |
| `trim-split` | `lordec-trim-split` | 修剪 + 将内部未纠区长到拆分成多条 | `-i`、`-o`（单线程） |

输出 corrected FASTA 中：**大写 = 已纠正确碱基，小写 = 未能纠正的区段**（随后交 trim /
trim-split 处理）。同一源码包还提供 `lordec-stats`（长读统计）与 `lordec-build-SR-graph`
（DBG 持久化，可被 `lordec-correct --graph` 复用），本驱动未包装为子命令，需要时经
`--extra-args` 透传或直接调用官方二进制。

## 快速开始

### 1. 安装环境

```bash
# Conda（官方推荐；bioconda 含 lordec 0.9）
mamba install -c bioconda -c conda-forge lordec
# 或一键脚本：bash native/install.sh（conda / 源码 make 双路线，见「环境安装」）
```

### 2. CLI 调用

```bash
# 主纠错：双端 Illumina（-2 逗号两文件）纠正 PacBio subreads（-i）
python main.py correct -2 illumina.1.fastq,illumina.2.fastq -i subreads.fasta -k 17 -s 3 -o corrected.fasta --threads 8
# 修剪头尾未纠区 / 修剪并拆分
python main.py trim -i corrected.fasta -o trimmed.fasta
python main.py trim-split -i corrected.fasta -o trimmed_split.fasta
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py correct -2 r1.fq,r2.fq -i pb.fa -k 17 -s 3 -o out.fa --dry-run   # 只打印构建出的命令
```

### 4. 容器运行（官方镜像）

```bash
# 直接拉官方 biocontainer（tag 见「环境安装」）；ENTRYPOINT 即 lordec 本体
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data -w /data \
    quay.io/biocontainers/lordec:0.9--h77376b9_3 \
    lordec-correct -2 /data/illumina.1.fastq,/data/illumina.2.fastq -i /data/subreads.fasta -k 17 -s 3 -o /data/corrected.fasta -T 8
```

Apptainer：

```bash
apptainer pull lordec.sif docker://depot.galaxyproject.org/singularity/lordec:0.9--h77376b9_3
apptainer run -B "$PWD":/data -H /data lordec.sif \
    lordec-correct -2 /data/illumina.1.fastq,/data/illumina.2.fastq -i /data/subreads.fasta -k 17 -s 3 -o /data/corrected.fasta -T 8
```

### 5. 测试

```bash
bash test/run_test.sh
```

`--schema` / `--list-commands` / argv 构造验证不依赖 lordec 二进制（未安装自动降级）；
已安装时以 `lordec-trim -h` 输出 Usage 作可用性冒烟（官方 bioconda recipe 判据）。

## 实战示例：PacBio subreads 混合纠错全流程（bam2fasta → correct → trim → trim-split）

以下为 PacBio 长读（subreads.bam）用 Illumina 双端短读做混合纠错的典型全流程；等价能力由
`native/main.py` 的 `correct` / `trim` / `trim-split` 子命令提供（见上「快速开始」）。

### 1. subreads.bam → subreads.fasta（bam2fasta）

```bash
# 二选一（按本机可用工具）：
#   A) PacBio 官方 pbtk（pbmm2 家族；conda: mamba install -c conda-forge -c bioconda pbtk）
#      bam2fasta subreads.bam  --numThreads 8  # 输出 subreads.fasta
#   B) samtools（若只需提取序列）
#      samtools fasta subreads.bam > subreads.fasta
```

### 2. lordec-correct：Illumina 短读纠错 PacBio 长读

```bash
# -2 双端 Illumina（逗号两文件，可 gzip）；-i 待纠错长读；-k k-mer；-s solid 阈值；-T 线程
lordec-correct -2 illumina.1.fastq,illumina.2.fastq -i subreads.fasta \
    -k 17 -s 3 -o corrected.fasta -T 8
# 小基因组（细菌等）可用 k=17/19、s=2/3；大基因组建议 k=21
```

产物 `corrected.fasta`：大写 = 已纠碱基，小写 = 未纠区段（残留在序列中，下一步修剪）。

### 3. lordec-trim：修剪头尾未纠区

```bash
lordec-trim -i corrected.fasta -o trimmed.fasta
```

### 4. lordec-trim-split：修剪并把内部未纠区拆开（可选，常用作替代第 3 步的最终形态）

```bash
lordec-trim-split -i corrected.fasta -o trimmed_split.fasta
```

> 拆出的短片段需在后续流程（比对/组装）中按 read 命名/坐标处理；若下游不接受拆分产物，
> 用第 3 步 trim 即可。纠错后 reads 可用于 Canu/Falcon/`ngs_*` 等组装与比对。

### 5. 参数说明

| 参数 | 适用子命令 | 说明 |
| --- | --- | --- |
| `-2` | correct | 参考短读集（FASTA/FASTQ，可 gzip）；单文件或双端逗号两文件（`R1,R2`） |
| `-i` | correct/trim/trim-split | 输入长读：correct 为待纠错 PacBio reads；trim/trim-split 为 corrected FASTA |
| `-k` | correct | k-mer 长度：细菌/小基因组 `17`–`19`，大基因组 `21` |
| `-s` | correct | solid k-mer 丰度阈值：短读中至少出现 s 次才可信，典型 `2`–`3` |
| `-o` | correct/trim/trim-split | 输出文件（corrected / trimmed FASTA） |
| `-T`/`--threads` | correct | 线程数（示例 `8`；trim/trim-split 单线程无此参数） |
| `--extra-args` | 全部 | 透传官方可选参数：correct 的 `--branch`/`--errorrate`/`--trials`/`--graph` 等（高级用法） |

***

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org 均有 lordec 0.9，
2026-09-08 核实），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
# Conda（bioconda 官方；0.9 覆盖 linux-64 + osx-64）
mamba create -n lordec-native -c conda-forge -c bioconda lordec=0.9
conda activate lordec-native
# 或在线直装：mamba install -c bioconda -c conda-forge lordec
lordec-trim -h   # 断言：输出含 Usage（lordec 无统一 --version）
```

Homebrew：homebrew-core（formulae.brew.sh/api/formula/lordec.json）与 brewsci/bio
（Formula/lordec.rb）两源均无 lordec 公式（2026-09-08 核实 404），故不提供 brew 安装方式。

> 一键安装可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境
> `lordec`；无 conda 时自动转官方源码 make 编译到 `~/software/lordec-<ver>`；
> 用法 `bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/lordec:0.9--h77376b9_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/lordec:0.9--h77376b9_3 \
    lordec-trim -i /data/corrected.fasta -o /data/trimmed.fasta
```

（`quay.io/biocontainers/lordec` 另有 0.9--he52c88d_2 / 0.9--h849b067_1 / 0.9--ha87ae23_0
与 0.6 系旧 tag 可查；0.9--h77376b9_3 为 linux-64 最新 build _3。）

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull lordec.sif docker://depot.galaxyproject.org/singularity/lordec:0.9--h77376b9_3
apptainer run -B $PWD:/data -H /data lordec.sif \
    lordec-correct -2 /data/illumina.1.fastq,/data/illumina.2.fastq -i /data/subreads.fasta -k 17 -s 3 -o /data/corrected.fasta
```

### 4. 二进制包安装（官方源码自编译，无 conda / docker 依赖）

官方没有预编译二进制 release，源码包以 gite.lirmm.fr 附件发布（curl HEAD 200 稳定直链，
官方仅发布 md5、无 sha256）：

```bash
# 官方源码包（lordec-src_0.9.tar.bz2，md5 dc57581bf2d265bd245f824a1e74209b —— 来自官方 bioconda recipe）
#   直链：https://gite.lirmm.fr/lordec/lordec-releases/uploads/800a96d81b3348e368a0ff3a260a88e1/lordec-src_0.9.tar.bz2
#   官方下载入口：https://gite.lirmm.fr/lordec/lordec-releases/wikis/home（wiki 空页面）→ 源码实际在 uploads 附件
#   依赖：make + C++ 编译器 + cmake + wget + HDF5/zlib 开发库（源码 Makefile 自动下载编译 GATB core 1.4.1
#     + Boost 1.64 头；见下方「历史留存/源码编译」注意项）
# 一键：bash native/install.sh --method source（编译到 ~/software/lordec-0.9，免 root）
# 或手动（与官方 conda build.sh 同款两步）：
curl -fsSL -o lordec-src_0.9.tar.bz2 \
    https://gite.lirmm.fr/lordec/lordec-releases/uploads/800a96d81b3348e368a0ff3a260a88e1/lordec-src_0.9.tar.bz2
tar -xjf lordec-src_0.9.tar.bz2 && cd lordec-src_0.9
make -j8 all                 # 自动下载并编译 GATB core（github.com/GATB/gatb-core v1.4.1，探测 200）
PREFIX="$HOME/software/lordec-0.9/bin" make install
export PATH="$HOME/software/lordec-0.9/bin:$PATH"
source ~/.bashrc
lordec-trim -h | grep -i Usage   # 断言
```

> 💡 源码 Makefile 默认会从 sourceforge 自动下载 Boost 1.64 头（kent.dl 镜像 2026-09-08 探测
> 超时）；若该步失败，请先装系统 Boost 头（Debian/Ubuntu `libboost-dev`；macOS `brew install
> boost`）再重试，或改走 conda 路线（最省事）。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；lordec 已装时 -h 冒烟
```

## 版本与来源（2026-09-08 逐渠道核实，禁止编造版本/URL/sha256）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| 官网 | ✅ v0.9 | http://www.atgc-montpellier.fr/lordec/ （→ /tool/lordec-hybrid-correction-of-long-reads/）；程序族 5 个；许可 CeCILL（A 系） |
| gite releases 项目 | ✅ public | https://gite.lirmm.fr/lordec/lordec-releases （id 1948；releases/tags API 为空 → 源码以 **uploads 附件**发布） |
| 官方源码直链 | ✅ `lordec-src_0.9.tar.bz2` | gite uploads 直链 curl 200（稳定、非一次性 token）；**md5 `dc57581bf2d265bd245f824a1e74209b`（官方 recipe 值；无 sha256）** |
| bioconda | ✅ **0.9**（0.6 亦在） | linux-64 + osx-64；最新 build `lordec-0.9-h77376b9_3`（linux）/ `lordec-0.9-h892528c_3`（osx），2022-02-24 上传；recipe 依赖 gatb=1.4.1 + boost + hdf5 + zlib |
| quay.io/biocontainers | ✅ **0.9--h77376b9_3** | 另有 0.9--he52c88d_2 / 0.9--h849b067_1 / 0.9--ha87ae23_0、0.6 系（0.6--0/1/--he941832_2） |
| depot.galaxyproject.org | ✅ 0.9 sif 直拉 | `lordec:0.9--h77376b9_3` 等 4 个 0.9 tag 均 200（与 quay biocontainers tag 互通） |
| nf-core modules | ❌ 404（modules/nf-core/lordec） | 无官方 Nextflow module |
| snakemake-wrappers | ❌ 404（bio/lordec） | 无官方 Snakemake wrapper |
| Homebrew（core / brewsci/bio） | ❌ 两源均 404 | 无公式 |
| GATB core（源码依赖） | ✅ v1.4.1 | github.com/GATB/gatb-core/archive/refs/tags/v1.4.1.tar.gz → 200（Makefile 自动下载源） |
| Boost 1.64（源码依赖，自动下载） | ⚠️ kent.dl.sourceforge.net 2026-09-08 探测超时（000） | 建议系统 Boost 头（libboost-dev / brew boost）或 conda 路线 |

* 官方渠道（bioconda → quay biocontainers → depot）齐全 → 判定 **container_official 官方路线**，
  `native/` 不维护 Dockerfile/Apptainer.def 自建配方。
* lordec 无统一 `--version` 输出；官方/bioconda 可用性判据 = `lordec-trim -h` 输出含 **Usage**。
* 版本锚点：bioconda/quay/depot 最新均停驻 0.9（自 2022-02 后无新 build；gite 项目最后活动
  2020-03）——0.9 即当前最新版（用户文档 0.9 与此一致）。

## 历史留存

历史用户文档中的安装路径（供追溯对照，**不硬编码为推荐步骤**）：

* **conda 推荐**：`mamba install -c bioconda -c conda-forge lordec` —— 与当前核实一致
  （bioconda lordec=0.9 官方维护），现登记于本 README「环境安装 §1」与 `native/environment.yml`。
* **历史源码编译**：LoRDEC 为 C++ 工程，依赖 **gatb-core**（GATB core 1.4.1，AGPL-3.0 分发）、
  **Boost** 与 **CMake/HDF5**；官方源码 Makefile 默认 `AUTOMATIC_LIBBOOST_LOCAL_INSTALL=yes`，
  make 时自动下载编译 GATB core 与 Boost 1.64 头（bioconda recipe 的 makefile.patch 证实，
  官方 conda 构建仅两步：`make CXX=... all` → `PREFIX=<bin> make install`）—— 现录入
  `native/install.sh` 的 source 路线与「环境安装 §4」。
* **手工预编译 gatb-core 变体**（历史用户文档方案，旧系统/离线、无自动下载时用；
  现代环境优先走官方 Makefile 自动路径或 conda）：LoRDEC 编译依赖 **gatb-core**
  （需 **cmake ≥2.8.4**、C++ 编译器）与 **Boost** 头，可先手工装依赖：

  ```bash
  # 1) 预编译 gatb-core v1.4.1（解压后工程在 gatb-core-1.4.1/gatb-core/ 子目录）
  wget https://github.com/GATB/gatb-core/archive/refs/tags/v1.4.1.tar.gz \
      -O ~/software/gatb-core-1.4.1.tar.gz
  tar zxf ~/software/gatb-core-1.4.1.tar.gz && cd gatb-core-1.4.1/gatb-core/
  mkdir build && cd build
  cmake -DCMAKE_INSTALL_PREFIX=$HOME/opt/gatb-core-1.4.1/ ../ && make -j 4 && make install
  cd ../../../
  # 2) 写依赖环境（历史教程用 /opt/biosoft 前缀 + ~/.bash_profile；此处改用户前缀 ~/opt 免 root）
  echo 'export LD_LIBRARY_PATH=$HOME/opt/gatb-core-1.4.1/lib:$LD_LIBRARY_PATH
  export C_INCLUDE_PATH=$HOME/opt/gatb-core-1.4.1/include:$C_INCLUDE_PATH' >> ~/.bashrc
  source ~/.bashrc
  # 3) 再按 §4 官方流程编译 LoRDEC 本体（其余依赖：Boost 头——Debian libboost-dev / brew boost）
  ```
* 早期产物（若存在于历史路径）不再维护；`correct`/`trim`/`trim-split` 命令语义由
  `native/main.py` 子命令承接。

## 性能优化约定

* 线程：驱动默认注入 `-T 4`（`optimization.default_cpus`）；`correct` 子命令建议
  `-T 8`（`optimization.per_subcommand_threads.correct=8`，用户显式 `--threads` 优先）；
  `trim`/`trim-split` 为单线程程序，`--threads` 占位不注入。
* 内存：LoRDEC 在内存中建 DBG，`optimization.default_mem_mb=16384`（调度语义建议）；大真核/
  脊椎动物数据请按官方 FAQ 经验给足内存。
* `--tmpdir` 覆盖 `$TMPDIR`（进程环境注入）；lordec 输出路径由 `-o` 指定。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# lordec native Conda 环境配方（native/environment.yml）
# 离线兜底：mamba env create -f native/environment.yml；在线推荐上方 mamba create 直装命令
# 说明：bioconda lordec=0.9（linux-64/osx-64）；官方镜像 quay.io/biocontainers/lordec 即由 bioconda 构建，
#       本地不再自建 Dockerfile/Apptainer.def（见上「环境安装」）。
name: lordec-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - lordec=0.9
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **官网**：<http://www.atgc-montpellier.fr/lordec/>
* **gite releases 项目**：<https://gite.lirmm.fr/lordec/lordec-releases>
* **官方源码包（0.9，md5 dc57581bf2d265bd245f824a1e74209b）**：<https://gite.lirmm.fr/lordec/lordec-releases/uploads/800a96d81b3348e368a0ff3a260a88e1/lordec-src_0.9.tar.bz2>
* **Bioconda 页面**：<https://anaconda.org/bioconda/lordec>（lordec=0.9）
* **Docker**：`docker pull quay.io/biocontainers/lordec:0.9--h77376b9_3`
* **Singularity（depot 预构建 sif）**：<https://depot.galaxyproject.org/singularity/lordec%3A0.9--h77376b9_3>
* **GATB core**（源码依赖，AGPL-3.0）：<https://github.com/GATB/gatb-core>
* **引用**：Salmela L, Rivals E. LoRDEC: accurate and efficient long read error correction.
  *Bioinformatics* 30(24):3506-3514 (2014). doi:10.1093/bioinformatics/btu538
