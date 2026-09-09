# bless 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器与 conda 渠道信息记录于此（2026-09-08 逐渠道核实）。
> BLESS / BLESS 2（Bloom-filter-based Error Correction Solution for NGS reads）是一个用于测序 reads 错误修正的工具，基于 k-mer 计数和 Bloom filter 进行错误检测和修正，支持多线程并行处理。无官方 GitHub 仓库、无官方 conda 包/镜像；官方发布站为 SourceForge bless-ec。

***

## native 实现

# bless / native — Bloom-filter reads 错误修正驱动（BLESS 1.02 / BLESS 2）

BLESS（UIUC Yun Heo 等，Bioinformatics 2014）与 BLESS 2（Bioinformatics 2016）的本地驱动实现
（`source_type: custom`、`type: native`），命令逻辑对齐官方 wiki + 用户文档 v1p02 示例。

bless 是**单条命令工具**（无子命令、无 `--help`/`-v`；无参运行即打印全部选项）。为对齐
SkillBase 分发接口与 Agent 路由，驱动提供单一 `correct` 子命令承载整条官方 CLI。

## 能力

| 子命令     | 官方命令形态（等价 CLI）                                             | 说明 |
| -------- | ------------------------------------------------------------ | -- |
| `correct` | `bless -read1 <R1> -read2 <R2> -prefix <P> -kmerlength <k> [-notrim] [-load <DB>] [-smpthread N]` | 双端 reads 错误修正（k-mer 计数 + Bloom filter + 修正） |
| （同上）     | `bless -read <single.fastq> -prefix <P> -kmerlength <k> [...]` | 单端（或已合并双端）reads 错误修正 |

参数白名单（argparse → 官方 flag）——全部经官方 wiki / 用户文档核实：

| 驱动参数 | 官方 flag | 必填 | 说明 |
| ---- | ----- | -- | -- |
| `-r/--read` | `-read` | 二选一 | 单端 FASTQ |
| `-1/--read1` + `-2/--read2` | `-read1` / `-read2` | 二选一 | 双端 FASTQ（须成对） |
| `-k/--kmerlength` | `-kmerlength` | 是 | k-mer 长度（默认 21；BLESS1 建议奇数，V0.20 起支持偶数） |
| `-p/--prefix` | `-prefix` | 是 | 输出前缀 `<输出目录名>/<文件前缀>` |
| `--notrim` | `-notrim` | 否 | 不修剪末端（官方默认修剪） |
| `-l/--load` | `-load` | 否 | 载入既有 Bloom filter（`<load>.bf.data/.bf.size`），跳过计数 |
| `--threads` | `-smpthread` | 否 | 线程（自动注入；默认 8） |
| `--extra-args` | 透传 | 否 | 白名单外选项（慎用） |

产物：双端 `<prefix>.1.corrected.fastq` + `<prefix>.2.corrected.fastq`（用户文档命名）；
单端输出文件名以官方实际为准（未核实）；同时生成 Bloom filter 转储 `<prefix>.bf.data` + `<prefix>.bf.size`
（供 `-load` 复用）。

## 用法

```bash
# CLI 直跑
python main.py correct -1 reads_1.fastq -2 reads_2.fastq -k 21 -p out/illumina --threads 8
python main.py correct -1 reads_1.fastq -2 reads_2.fastq -k 21 -p out/frag --notrim
python main.py correct -1 reads_1.fastq -2 reads_2.fastq -k 21 -p out/jumping -l out/frag

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
python main.py correct -1 a.fastq -2 b.fastq -k 21 -p out --dry-run   # 只打印命令
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：双端 reads 错误修正（预处理 → 组装/比对前一步）

以下为测序数据质控预处理阶段的典型用法（源自用户教学文档 BLESS 章节，路径改写为无硬编码的
通用形式；等价能力由 `native/main.py` 的 `correct` 子命令提供，见上「用法」）。

### 1. 主版本流程（CentOS 8 示例改写）：FastUniq 去重后 → BLESS 修正

```bash
mkdir -p corrected && cd corrected
# FastUniq 去重后的双端数据（R1/R2 各一行列出后去重，此处直接引用去重产物）
bless -read1 ../FastUniq/illumina.1.fastq -read2 ../FastUniq/illumina.2.fastq \
  -kmerlength 21 -prefix illumina
# 产物 illumina.1.corrected.fastq / illumina.2.corrected.fastq → 软链回原名供下游使用
ln -s illumina.1.corrected.fastq illumina.1.fastq
ln -s illumina.2.corrected.fastq illumina.2.fastq
```

### 2. 多文库共享 k-mer 库（CentOS 6 示例改写）：先用准确的 paired-end 建库，再对 mate-pair 校正

```bash
# 片段文库（fragment，paired-end）→ 建 Bloom filter 库（-prefix fragment 同时产出 .bf.data/.bf.size）
bless -read1 ../FastUniq/fragment.1.fastq -read2 ../FastUniq/fragment.2.fastq \
  -kmerlength 21 -notrim -prefix fragment

# jumping（mate-pair）文库 → -load fragment 载入同一 k-mer 库，跳过重复计数
bless -read1 ../FastUniq/jumping.1.fastq -read2 ../FastUniq/jumping.2.fastq \
  -load fragment -kmerlength 21 -notrim -prefix jumping

ln -s fragment.1.corrected.fastq fragment.1.fastq
ln -s fragment.2.corrected.fastq fragment.2.fastq
ln -s jumping.1.corrected.fastq jumping.1.fastq
ln -s jumping.2.corrected.fastq jumping.2.fastq
```

### 3. 参数说明

| 参数 | 说明 |
| --- | --- |
| `-read1` / `-read2` | 输入双端测序数据（R1 / R2 FASTQ） |
| `-kmerlength` | k-mer 长度（示例 21；奇数更佳，V0.20 起支持偶数） |
| `-prefix` | 输出前缀（`<输出目录名>/<文件前缀>`；产物 `<prefix>.1/2.corrected.fastq`） |
| `-notrim` | 不进行末端修剪（官方默认修剪；用户文档 CentOS 6 脚本使用） |
| `-load` | 加载已有 k-mer 库/Bloom filter（`-load fragment` 复用 fragment 的 `.bf.data/.bf.size`） |
| `-smpthread` | 每节点线程数（默认 = SMP 核数；驱动默认注入 8） |

> 💡 运行注意事项（用户文档记载）：
> 1. 编译需高版本 GCC + MPICH（官方测试 GCC 4.9.2 + MPICH 3.1.3 / OpenMPI 1.8.2）；
> 2. 运行时需在当前工作目录（CWD）下存在 `kmc/bin/kmc`（用户文档用
>    `alias bless='mkdir -p kmc/bin/; cp <安装目录>/kmc/bin/kmc kmc/bin/; bless'` 保证；
>    本模块 install.sh 的 launcher 与 Docker/Apptainer 的 `/usr/local/bin/bless` 已内置同样逻辑）；
> 3. 主机名解析问题可能使 BLESS 无法运行：`hostname localhost` 还原后再运行
>    （launcher 已做 best-effort 兜底：hostname 不可解析时写 `/etc/hosts`，需 root 生效）。

### 4. 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；已装真 bless 时做无参用法冒烟
BLESS_FULL_SMOKE=1 bash test/run_test.sh   # 额外跑完整修正冒烟（合成 reads + KMC）
```

## 环境安装（自建兜底：BLESS 1.02 无官方镜像 / conda 包，apt 最小化源码编译）

> ⚠️ **版本现状（2026-09-08 核实）**：官方渠道 bioconda → quay.io/biocontainers → depot.galaxyproject.org
> **全部没有** BLESS（bioconda 无 bless 包；conda-forge/bless 为**同名异义**的 Python CLI 日志包 v0.4.0，
> 与 NGS BLESS 无关，**禁止**安装）；nf-core / snakemake-wrappers 无模块；Homebrew 无公式；
> GitHub 无官方仓库（nsaunders/bless、sfu-compbio/bless、sfu-compbio/bless2 均 404）。
> 官方发布站 = SourceForge bless-ec，最新发布 `bless.v1p02.tgz`（BLESS 1.02 / BLESS 2，2015-06-10，GPLv3 源码，
> 无预编译二进制）。因此走**自建兜底**：Dockerfile/Apptainer.def（debian:bookworm-slim + apt 构建依赖
> g++/make/mpich + 官方源码 make，禁 miniconda），宿主机源码安装见「### 4」。

### 1. Conda / brew（包管理器安装）

**不提供 conda / brew 路线，理由（2026-09-08 核实）**：

```bash
# ❌ bioconda 无 bless 包（api.anaconda.org/package/bioconda/bless → 404；bioconda-recipes recipes/bless → 404）
# ❌ conda-forge/bless 是「同名异义」的 Python CLI 日志包（v0.4.0，MIT）——不是 NGS BLESS，切勿安装
# ❌ Homebrew：homebrew-core（formulae.brew.sh/api/formula/bless.json → 404）与
#    brewsci/bio（Formula/bless.rb → 404）均无公式
```

> 离线 / 无 root 环境的源码编译工具链兜底见文末「Conda 环境」（native/environment.yml：python+pyyaml+
> make+mpich，**不含 bless 本体**）；一键安装直接 `bash native/install.sh`（source 源码编译到
> `~/software/bless-1.02`，免 root、不写 /opt/biosoft）。

### 2. Docker（自建镜像，官方渠道无）

```bash
# 构建（context=modules/ 层，携带 base.py + 软件级 meta.yaml）
docker build -t bioskills/bless:1.02 -f modules/bless/native/Dockerfile modules/
# 运行：注意必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/bless:1.02 \
    -read1 /data/reads_1.fastq -read2 /data/reads_2.fastq -kmerlength 21 -prefix out/illumina -notrim
# 驱动 main.py（镜像内已放 base.py + 软件级 meta；--entrypoint 切到 python3）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/bless:1.02 \
    /opt/skill/main.py correct -1 /data/reads_1.fastq -2 /data/reads_2.fastq -k 21 -p out/illumina
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 无预构建 bless sif（目录列表核实无 bless* 条目）→ 本地自建：

```bash
cd modules && apptainer build ../bless.sif bless/native/Apptainer.def && cd ..
apptainer run -B $PWD:/data -H /data bless.sif \
    -read1 /data/reads_1.fastq -read2 /data/reads_2.fastq -kmerlength 21 -prefix out/illumina
```

### 4. 源码安装（官方 SourceForge 源码归档 → make）

官方无预编译二进制（发布资产为源码 tgz；V1.01 起 tgz 内含全部依赖库 Boost/sparsehash/klib/KMC/
murmurhash3/zlib/pigz，编译仅需 make + g++ + MPI 开发库）：

```bash
# 依赖：make + g++ + MPI（官方测试 GCC 4.9.2 + MPICH 3.1.3 / OpenMPI 1.8.2）
# Debian/Ubuntu：sudo apt-get install -y --no-install-recommends build-essential g++ make mpich libmpich-dev
# macOS：brew install mpich gcc

# 一键安装（推荐；下载 → make → ~/software/bless-1.02，launcher 自动处理 kmc/bin/kmc + hostname）
bash native/install.sh                 # 等价 --method source
bash native/install.sh --prefix ~/opt/bless

# 或手动
cd ~/software
wget https://downloads.sourceforge.net/project/bless-ec/bless.v1p02.tgz
tar zxf bless.v1p02.tgz                # 顶层目录 v1p02（用户文档 mv v1p02 → BLESS 佐证）
cd v1p02 && make -j 4                  # 产物 ./bless 与 ./kmc/bin/kmc
mkdir -p ~/software/bless-1.02/bin && cp bless ~/software/bless-1.02/bless
cp -r kmc ~/software/bless-1.02/       # 运行时 launcher 需要把 kmc/bin/kmc 拷到 CWD
echo 'export PATH=$PATH:~/software/bless-1.02/bin' >> ~/.bashrc
source ~/.bashrc
```

> 💡 运行时请从 reads 所在目录运行（launcher 会把 `kmc/bin/kmc` 放到 CWD）；bless 无 `--version`，
> 无参运行打印全部选项即安装成功（含 `-kmerlength`/`-prefix`）。

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言恒跑；已装真 bless 时无参用法冒烟
```

## 版本与来源（2026-09-08 逐渠道核实，禁止臆造）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| SourceForge bless-ec（官方） | ✅ 最新 `bless.v1p02.tgz`（2015-06-10，6.0 MB，GPLv3） | 版本线：BLESS 1 = V0.11–V0.24（2013-10 ~ 2015-01）；BLESS 2 = V1.00–V1.02（wiki 标注 V1.00+ aka BLESS 2，2015-05 ~ 2015-06），**主程序名仍为 bless** |
| 官方 wiki（用法/参数） | ✅ <https://sourceforge.net/p/bless-ec/wiki/Home/> | `-read`（SE）/`-read1`/`-read2`（PE）/`-prefix`/`-kmerlength`/`-load`/`-smpthread`；`make` 安装；依赖 GCC+MPI |
| GitHub | ❌ 无官方仓库 | nsaunders/bless、sfu-compbio/bless、sfu-compbio/bless2 均 404；精确名搜索无 NGS BLESS 仓库 |
| bioconda | ❌ 无 bless 包 | api.anaconda.org/package/bioconda/bless → 404；bioconda-recipes recipes/bless → 404 |
| conda-forge | ⚠️ 同名异义 | conda-forge/bless = Python CLI 日志包 v0.4.0（MIT）——**非 NGS BLESS** |
| quay.io/biocontainers | ❌ 无 | biocontainers 镜像由 bioconda 自动构建，bioconda 无 bless → 无对应镜像 |
| depot.galaxyproject.org | ❌ 无 sif | /singularity/ 目录列表核实无 bless* 条目 |
| nf-core modules | ❌ 404 | modules/nf-core/bless |
| snakemake-wrappers | ❌ 404 | bio/bless |
| Homebrew（core / brewsci/bio） | ❌ 两源均 404 | 无公式；另注意 macOS 自带 `/usr/sbin/bless`（启动盘工具）同名异义 |
| Docker Hub 官方 | ❌ 无官方镜像 | — |
| sha256 | ⚠️ 未核实 | 录入规范禁真实下载，未核对 bless.v1p02.tgz 摘要（install.sh 默认跳过并提示，可 `--sha256` 显式提供） |

* 判定：官方渠道（bioconda → quay biocontainers → depot）全无 →「无官方维护」→ 自建配方（版本差异与
  依据在 `meta.yaml software_versions` 中声明）。
* BLESS：Heo Y, et al. Bioinformatics 30(10):1354-1362 (2014)；BLESS 2：Heo Y, et al.
  Bioinformatics 32(15):2369-2371 (2016)。
* 参数以官方 wiki + 用户文档示例为准；白名单未收录的其它选项（无参帮助输出中的附加开关）未核实，请走
  `--extra-args` 透传。

## 历史留存

用户教学文档（BLESS 章节）原示例为 **BLESS v1p02（bless-ec，即 BLESS 2 最新发布）**：安装段硬编码
`wget https://sourceforge.net/projects/bless-ec/files/bless.v1p02.tgz` 解压到 `/opt/biosoft/` 并
`mv v1p02 BLESS`、`make -j 4`、把 `~/software` 前缀写入 PATH 并做
`alias bless='mkdir -p kmc/bin/; cp <安装目录>/kmc/bin/kmc kmc/bin/; bless'`；示例目录硬编码
`/home/train/02|03.sequencing_data_quality_control/BLESS`、`source ~/.bashrc.gcc`（高版本 GCC）与
`source ~/.bashrc.mpich`（MPICH）环境、`-notrim`/`-load fragment` 用法、`hostname localhost`
主机名修复提示，以及 `ln -s *.corrected.fastq` 回链下游。上述 `/opt/biosoft`、`/home/train`、
`.bashrc.gcc/.bashrc.mpich` 教学硬编码**已按仓库规范改写**（用户前缀 `~/software/bless-1.02`、
launcher 内置 kmc 拷贝与 hostname 兜底），语义由 `native/main.py` 的 `correct` 子命令 + 本 README
「实战示例」承接。

## 性能优化约定

* BLESS 对 k-mer 与内存敏感：k-mer 计数（KMC）会占大量内存与临时磁盘（官方 V0.24 起 KMC 最大内存可
  固定 4 GB），Bloom filter 阶段对长 reads 数据同样吃内存 → `optimization.default_mem_mb: 16384`。
* 线程：驱动默认注入 `-smpthread 8`（`optimization.default_cpus`）；用户显式 `--threads` 优先。
* `--tmpdir` 覆盖 `$TMPDIR`（`TMPDIR` 环境变量已声明 `{tmpdir}`）；KMC 临时文件与中间产物建议放在
  大容量临时盘。
* 多文库批量数据：先跑一次建 Bloom filter（`-prefix lib`），后续文库 `-load lib` 跳过重复计数
  （用户文档 fragment/jumping 范例）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bless native Conda 环境配方（native/environment.yml）
# 离线兜底：可另存为 yml 后 mamba env create -f native/environment.yml
# 说明：bioconda 无 bless 包（conda-forge/bless 同名异义勿装）→ 本环境只提供 main.py 运行依赖
#       （python/pyyaml）与源码编译辅助（make/mpich）；bless 本体需 SourceForge 源码 make。
name: bless-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - pyyaml>=6.0
  - make
  - mpich
```

## 容器与 Conda 链接

* **官方发布站**：<https://sourceforge.net/projects/bless-ec/>（源码归档 + wiki + GPLv3）
* **官方 wiki（用法/参数）**：<https://sourceforge.net/p/bless-ec/wiki/Home/>
* **官方源码归档**：<https://downloads.sourceforge.net/project/bless-ec/bless.v1p02.tgz>（下载页 <https://sourceforge.net/projects/bless-ec/files/>）
* **Bioconda 页面（无此包）**：<https://anaconda.org/bioconda/bless>（404）；conda-forge/bless 同名异义页 <https://anaconda.org/conda-forge/bless>
* **自建配方**：`modules/bless/native/Dockerfile` + `Apptainer.def`（debian:bookworm-slim + g++/make/mpich + SourceForge 源码 make v1.02）
* **宿主一键安装**：`bash modules/bless/native/install.sh --help`（源码编译到 `~/software/bless-1.02`）
