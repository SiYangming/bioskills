# gce 软件模块

> 汇总说明：本 README 说明 gce（GCE, Genome Characteristics Estimation 1.0.0）的唯一实现
> （native）；安装方式见下方各节，容器与 conda 信息记录于此。
> 软件为历史遗留（BGI 官方发布源 2026-09 已停服；官方无任何
> conda/容器渠道），新项目建议改用 GenomeScope 2.0 + Jellyfish。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/gce/` **不存在**（2026-09 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/gce> 返回 404）。
* **snakemake-wrappers**：`bio/gce` **不存在**（2026-09 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/gce> 返回 404）。
* **Homebrew**：homebrew-core（`formulae.brew.sh/api/formula/gce.json` 404）与 brewsci/bio
  （`Formula/gce.rb` 404）两源均无 gce 公式（2026-09 核实）→ README 不登记 brew 安装块。

> 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均无 gce 包/镜像**
> （2026-09 逐渠道核实：bioconda API 404、quay.io/biocontainers/gce 不存在、
> depot.galaxyproject.org/singularity/gce:1.0.0--0 404）→ `native/` 提供**自建**
> Dockerfile / Apptainer.def（debian:bookworm-slim + g++/make + 官方 tarball 源码 make，linux/amd64）。

***

## native 实现

# gce / native — k-mer 基因组特征估计驱动（1.0.0）

GCE 1.0.0 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对照官方
tarball。

## 功能

两支程序对应组装前基因组 survey 的两段链路：

| 子命令              | 命令                                                                                  | 作用                                            |
| ---------------- | ----------------------------------------------------------------------------------- | --------------------------------------------- |
| `kmer_freq_hash` | `kmer_freq_hash -k <k> -l <reads.list> -t <N> [-i <init>] -o <0\|1> -p <prefix>`     | reads → k-mer 频数统计（`<prefix>.freq.gz` / `<prefix>.freq.stat`） |
| `gce`            | `gce -f <freq.stat> [-c <cvg>] [-g <kmer_num>] [-m <mode>] [-D <dis>] [-b <bias>] [-H 1]` | 频率谱 → 基因组大小/重复/杂合度估计（stdout 表 + stderr 日志） |

## 用法

```bash
# CLI 直跑
python main.py kmer_freq_hash -l reads.list -k 21 -p out --threads 8
python main.py gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 -o out.table --log out.log
python main.py gce -f out.freq.stat -g 273206457 -H --log out.h1.log     # 杂合模式

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--threads` 仅 kmer_freq_hash 注入 `-t`；
gce 本身单线程）。

## 实战示例：组装前 k-mer 基因组 survey

GCE (Genome Characteristics Estimation)  用贝叶斯模型从 k-mer 频率谱估计基因组大小、重复序列比例与杂合度，是早期华大自主组装
流程的 survey 工具。以下为文档给出的典型用法；等价能力由 `native/main.py` 的
`kmer_freq_hash` / `gce` 子命令提供（见上「用法」）。

### 1. 生成 reads 文件列表

```bash
mkdir -p GCE && cd GCE
ls /path/to/FastUniq/illumina.?.fastq > reads.list
```

### 2. 计算 k-mer 频率

```bash
# -k 21 k-mer 长度；-l reads.list 输入列表；-t 8 线程
# -i 80000000 初始 hash 表大小（估计的不同 k-mer 数）；-o 0 不输出每个 k-mer 序列
# -p out 输出前缀（生成 out.freq.gz / out.freq.stat）
kmer_freq_hash -k 21 -l reads.list -t 8 -i 80000000 -o 0 -p out &> kmer_freq.log
```

### 3. 评估基因组特征

```bash
# -f out.freq.stat 频率统计；-g 总 k-mer 数（取自 kmer_freq.log 的 Kmer_individual_num）
# -m 1 连续模型；-D 8 峰间距；-b 1 有测序偏好；-H 1 杂合模式（纯合省略）
gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 > out.table 2> out.log
# 杂合基因组：
gce -f out.freq.stat -c 21 -g 273206457 -m 1 -D 8 -b 1 -H 1 > out.h1.table 2> out.h1.log
```

### 4. K-mer 分布图（可选，R/ggplot2）

```bash
# 格式转换后交给 R 绘制（正/负链 k-mer 深度分布）
perl -e 'print "dep\tnum\n";while (<>) {print}' out.freq.stat > 11
R --vanilla --slave <<'RSCRIPT'
a <- read.table("11", header=TRUE)
library("ggplot2")
png(file="dep_num.png", bg="transparent")
qplot(dep, num, data=a, ylim=c(0,3e5), xlim=c(0,180), geom=c("line"))
dev.off()
RSCRIPT
```

### 5. 参数说明

| 参数（子命令）                     | 说明                                     |
| --------------------------- | -------------------------------------- |
| `kmer_freq_hash -k`         | k-mer 长度（9~27，默认 17）                   |
| `kmer_freq_hash -l`         | reads 路径列表（每行一个）                       |
| `kmer_freq_hash -t`         | 线程数                                    |
| `kmer_freq_hash -i`         | 每线程初始 hash 表大小                          |
| `kmer_freq_hash -o`         | 是否输出每个 k-mer 序列（1=是；0=否，省时）             |
| `kmer_freq_hash -p`         | 输出前缀                                   |
| `gce -f`                    | k-mer 深度频率文件（`.freq.stat`）              |
| `gce -g`                    | 总 k-mer 数                              |
| `gce -c`                    | unique k-mer 期望深度（`-H` 时常与主峰配合）        |
| `gce -m`                    | 0=离散（默认）/ 1=连续                        |
| `gce -D`                    | 连续模型峰间距                               |
| `gce -b`                    | 测序偏好 1=有 / 0=无                         |
| `gce -H`                    | 杂合模式（加 `-H 1`）                         |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**无 gce 包/镜像**
（2026-09 核实）；官方仅以 tarball 形式分发（官方发布源 2026-09 已停服）。官方 tarball
**同时包含已编译的 x86_64 二进制与源码**，两条官方路线均保留；因官方无镜像，本地另维护
容器配方（Dockerfile / Apptainer.def）兜底。

### 1. 官方预编译二进制（tarball 内）

```bash
# 官方 tarball 内自带 2012 年编译的 gce 与 kmerfreq 二进制（Linux x86_64）
# 一键：拉取 tarball 后直接布署随包预编译二进制（不编译）
bash native/install.sh --method binary --prefix ~/software/gce-1.0.0
export PATH="$HOME/software/gce-1.0.0/bin:$PATH"
gce -h    # 断言：打印 Version: 1.0.0
```

> ⚠️ 预编译二进制为 2012 年产物，对现代 glibc 的兼容性**未核实**；若运行报错请改用 §2 源码编译。

### 2. 官方源码编译（并列保留）

```bash
# 一键：下载官方 tarball → make 重编译 gce → 布署到用户前缀（免 root，写 PATH）
bash native/install.sh                       # 默认 --method source
export PATH="$HOME/software/gce-1.0.0/bin:$PATH"
gce -h                                       # 断言：Version: 1.0.0
```

或手动编译（BGI 官方文档记载的传统方式，`/opt/biosoft` 前缀、需 root）：

```bash
# 1. 下载 tarball
wget https://github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz -P ~/software/

# 2. 解压到 /opt/biosoft/（需 root）
sudo tar zxf ~/software/gce-1.0.0.tar.gz -C /opt/biosoft/

# 3. 编译 k-mer 频率计算模块（kmerfreq/kmer_freq_hash/）
cd /opt/biosoft/gce-1.0.0/kmerfreq/kmer_freq_hash/
make

# 4. 编译主程序（g++ -o gce gce.cpp）
cd /opt/biosoft/gce-1.0.0/
make

# 5. 添加环境变量
echo 'PATH=$PATH:/opt/biosoft/gce-1.0.0/' >> ~/.bashrc
echo 'PATH=$PATH:/opt/biosoft/gce-1.0.0/kmerfreq/kmer_freq_hash/' >> ~/.bashrc
source ~/.bashrc

# 6. 断言
gce -h    # 打印 Version: 1.0.0

# R 用于 k-mer 作图（源码编译非常耗时，建议用系统包管理器安装）
# 见系统配置
```

> ⚠️ kmerfreq 子程序（kmer_freq_hash 等）为 2012 年预编译 x86_64 二进制、**无源码**，
> `make` 在该目录可能无目标（`Nothing to be done`）；若预编译二进制在现代 glibc 上不可用，
> 无源码重编译途径——需改用 `install.sh` 或容器方案。主程序 `gce` 有 `gce.cpp` + `Makefile`，可正常重编译。

> 来源说明：官方发布源已停服，`install.sh` 按序尝试两个镜像（内容相同、sha256 一致）：
> ① **版本化 release（首选）** <https://github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz>
> （2026-09 核实 200）；② 社区镜像 <https://github.com/nottwy/genome-character-estimator>
> （`gce-1.0.0.tar.gz`，2026-09 核实 200，sha256 已内嵌）。官方 GitHub 后继仓库
> <https://github.com/fanagislab/GCE> 提供 gce-1.0.2 / gce-alternative（版本不同，未纳入本模块 1.0.0）。

### 3. Conda / brew（包管理器安装）

* **conda**：bioconda **无 gce 包**（2026-09 核实 `api.anaconda.org/package/bioconda/gce` 404）
  → 无 conda 安装路线。
* **brew**：homebrew-core 与 brewsci/bio 两源**均无** gce 公式（2026-09 核实 404）→ 不登记 brew 块。

### 4. Docker（本地自建镜像，官方无镜像）

```bash
# 官方无 gce 镜像 → 用本模块 Dockerfile 自建（context 必须是 modules/ 层）
docker build -t bioskills/gce:1.0.0 -f modules/gce/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/gce:1.0.0 \
    -f /data/out.freq.stat -g 273206457 -m 1 -D 8 -b 1
```

### 5. Apptainer / Singularity（本地自建镜像）

```bash
# 官方无 depot 预构建 sif → 用本模块 Apptainer.def 自建
apptainer build gce.sif modules/gce/native/Apptainer.def
apptainer run -B $PWD:/data -H /data gce.sif -f /data/out.freq.stat -g 273206457
```

## 测试

```bash
bash test/run_test.sh   # 合成数据 + argv 构造验证；GCE 未安装时跳过真实冒烟
```

## 版本

* GCE 1.0.0（`gce -h` 打印 `Version: 1.0.0`）
* 构建路线：官方 tarball（预编译二进制 + 源码并列）；官方无 conda/容器渠道 → 本地自建容器配方
* nf-core / snakemake-wrappers 均无官方模块（2026-09 核实 404）

***

## 容器与 Conda 链接

* **官方渠道**：无（bioconda / quay.io/biocontainers / depot.galaxyproject.org 2026-09 均无）
* **官方 tarball（版本化 release，首选）**：<https://github.com/SiYangming/GCE/releases/download/gce-1.0.0/gce-1.0.0.tar.gz>
* **官方 tarball（社区镜像，fallback）**：<https://github.com/nottwy/genome-character-estimator>
* **官方后继仓库**：<https://github.com/fanagislab/GCE>（gce-1.0.2 / gce-alternative）
* **本地自建镜像**：`modules/gce/native/Dockerfile`、`modules/gce/native/Apptainer.def`
* 安装方式（本地）：`bash native/install.sh`（源码编译，默认 `~/software/gce-1.0.0`）
